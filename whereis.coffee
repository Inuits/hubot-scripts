# Description:
#   inuit finder script by Joey
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_PAMELA_MAC_URL
#   HUBOT_PAMELA_LOCATIONS_URL
#   HUBOT_PAMELA_USERNAME
#   HUBOT_PAMELA_PASSWORD
#
# Commands:
#   hubot where is $person ?  - returns the location of $person, if known
#   hubot where is everyone ?  - returns the location of everyone Pamela know about.
#   hubot is $user in $office - respsonds with yes or no and extra info
#   hubot notify when ($user/someone) arrives [in $office] - hubot will tell you when $user (or anyone) arrives [in $office]
#   hubot stop notifying when ($user/someone) arrives [in $office] - hubot will stop telling you when $person/someone arrives [in $office
#
# Author:
#   JoeyDP

url1 = process.env.HUBOT_PAMELA_MAC_URL
url2 = process.env.HUBOT_PAMELA_LOCATIONS_URL

auth = new Buffer("#{process.env.HUBOT_PAMELA_USERNAME}:#{process.env.HUBOT_PAMELA_PASSWORD}").toString('base64')

module.exports = (robot) ->
  # hubot where is $person ?  - returns the location of $person, if known
  robot.respond /where is (.+)/i, (msg) ->
    personName = msg.match[1].trim()
    msg.envelope.user.type = 'direct' # respond in personal chat

    if personName.toLowerCase() == 'hubot'
      msg.send "I'm right here!"
      return

    if personName.toLowerCase() == 'everyone'
      personName = ''

    findDevices personName, (devices) ->
      if Object.keys(devices).length == 0 and personName != ''
        msg.send "#{personName} is not on my list! Add them with http://pamela.inuits.eu/edit/" if !found?
        return

      for device, place of devices
        if place?
          msg.send "Found #{device} in #{place}."
          found = true

      msg.send "Couldn't locate any of #{personName}'s devices." if !found

  # hubot is $user in $office - respsonds with yes or no and extra info
  robot.respond /is (.+) in (.+)/i, (msg) ->
    personName = msg.match[1].trim()
    officeName = msg.match[2].trim()
    msg.envelope.user.type = 'direct' # respond in personal chat

    if personName.toLowerCase() == 'hubot'
      msg.send "I'm right here!"
      return

    findDevices personName, (devices) ->
      if Object.keys(devices).length == 0
        msg.send "#{personName} is not on my list! Add them with http://pamela.inuits.eu/edit/" if !found?
        return

      for device, place of devices
        if place?
          if place.toLowerCase() == officeName.toLowerCase()
            msg.send "Yes, I found #{device} in #{place}."
            return
          else
            msg.send "No, but I did find #{device} in #{place}."
            return

      msg.send "Couldn't find #{personName} anywhere."


  # hubot notify when $user arrives in $office" - hubot will tell you when $user arrives in $office
  robot.respond /notify when (.+) arrives(?: in (.+))?/i, (msg) ->
    personName = msg.match[1].trim()
    officeName = (msg.match[2] or '').trim()
    msg.envelope.user.type = 'direct' # respond in personal chat

    if personName.toLowerCase() == "someone"
      personName = ''

    if personName.toLowerCase() == 'hubot'
      msg.send "I'm right here!"
      return

    if personName != '' and officeName != ''
      findDevices personName, (devices) ->
        if Object.keys(devices).length == 0
          msg.send "#{personName} is not on my list! Add them with http://pamela.inuits.eu/edit/" if !found?
          return

        for device, place of devices
          if place?
            if place.toLowerCase() == officeName.toLowerCase()
              msg.send "#{personName} is already in #{officeName}."
              return

    toNotify = robot.brain.get('toNotify') or []
    for item, index in toNotify
      if item.person == personName and item.place == officeName and item.room == msg.envelope.user.name
        msg.send "I was already going to!"
        return
    toNotify.push({'person':personName, 'place':officeName, 'room':msg.envelope.user.name, 'msg':msg})
    robot.brain.set 'toNotify', toNotify
    msg.send "I will notify you."


  # hubot stop notifying when $person/someone arrives [in $office] - hubot will stop telling you when someone arrives in $office
  robot.respond /stop notifying when (.+) arrives(?: in (.+))?/i, (msg) ->
    personName = msg.match[1].trim()
    officeName = (msg.match[2] or '').trim()

    if personName.toLowerCase() == "someone"
      personName = ''


    toNotify = robot.brain.get('toNotify') or []

    for item, index in toNotify
      if item.person == personName and item.place == officeName and item.room == msg.envelope.user.name
        toNotify.splice(index, 1)

    robot.brain.set 'toNotify', toNotify
    msg.send "I will stop notifying you."


  findDevices = (name, callback) ->
    name = name.trim().toLowerCase()
    devices = []

    req = robot.http(url1)
    req.header('Authorization', "Basic #{auth}")
    req.get() (err, res, body) ->
      if err
        msg.send "Pamela says: #{err}"
      else
        data = (item.split(',')[1] for item in body.split '\n')
        for device in data
          if device.toLowerCase().search(name) >= 0
            devices.push(device)

        req = robot.http(url2)
        req.header('Authorization', "Basic #{auth}")
        req.get() (err, res, body) ->
          if err
            msg.send "Pamela says: #{err}"
          else
            data = JSON.parse(body)
            places = {}
            for item in data
              [device, place] = item.split '@'
              places[device] = place

            ret = {}
            for device in devices
              ret[device] = places[device]
            callback ret

  # function that gets called by updateArrivals when someone arrives somewhere
  newArrival = (device, place, arrived=true) ->
    toNotify = robot.brain.get('toNotify') or []
    for item, index in toNotify
      deviceCorr = device.toLowerCase().trim().search(item.person) >= 0
      placeCorr = place.toLowerCase().trim().search(item.place) >= 0
      if deviceCorr and placeCorr
        unless item.msg?
          toNotify.splice(index, 1)
          robot.brain.set 'toNotify', toNotify
          continue

        if arrived
          item.msg.send "#{device} just arrived at #{place}."
          # robot.messageRoom(item.room, "#{device} just arrived at #{place}.")
          if item.person != '' # if a specific person was requested, only notify once
            toNotify.splice(index, 1)
            robot.brain.set 'toNotify', toNotify
        else
            item.msg.send "#{device} left #{place}."
          # robot.messageRoom(item.room, "#{device} left #{place}.")
        return

  # checks for updates from Pamela
  updateArrivals = () ->
    lastPlaces = robot.brain.get('lastPlaces') or []
    # format: {device:place, ... }

    req = robot.http(url2)
    req.header('Authorization', "Basic #{auth}")
    req.get() (err, res, body) ->
      if err
        console.log "Pamela says: #{err}"
      else
        # fetch new places
        data = JSON.parse(body)
        newPlaces = {}
        for item in data
          [device, place] = item.split '@'
          newPlaces[device] = place

      # compare lastPlaces with newPlaces
      for device, lastPlace of lastPlaces
        newPlace = newPlaces[device]
        if newPlace?
          if newPlace != lastPlace
            newArrival device, newPlace
        else
          newArrival device, lastPlace, false

      # compare newPlaces with lastPlaces
      for device, newPlace of newPlaces
        lastPlace = lastPlaces[device]
        unless lastPlace?
          newArrival device, newPlace

      robot.brain.set 'lastPlaces', newPlaces


  setInterval updateArrivals, 10000
