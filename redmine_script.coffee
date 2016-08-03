# Description:
#   Showing of redmine issue via the REST API
#   It also listens for the #nnnn format and provides issue data and link
#   Eg. "Hey guys check out #273"
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_REDMINE_SSL
#   HUBOT_REDMINE_BASE_URL
#   HUBOT_REDMINE_TOKEN
#   HUBOT_REDMINE_IGNORED_USERS
#
# Commands:
#   hubot (redmine|show) me <issue-id> - Show the issue status
#   hubot show (my|user's) issues - Show your issues or another user's issues
#   hubot assign <issue-id> to <user-first-name> ["notes"] - Assign the issue to the user (searches login or firstname)
#   hubot update <issue-id> with "<note>" - Adds a note to the issue
#   hubot add <hours> hours to <issue-id> ["comments"] - Adds hours to the issue with the optional comments
#   hubot link me <issue-id> - Returns a link to the redmine issue
#   hubot set <issue-id> to <int>% ["comments"] - Updates an issue and sets the percent done
#   hubot add issue to "<project>" [traker <id>] with "<subject>" - Creates a new issue with due date 1 month from now
#   hubot create project ["<name>" as] <id> [under <parent>]
#   hubot issue search [all] <keyword> - searches for issues on redmine. Gives you the first 5 found. unless all is present, hubot only looks for open tickets.
#
# Notes:
#   <issue-id> can be formatted in the following ways: 1234, #1234,
#   issue 1234, issue #1234
#
# Author:
#   robhurring

Redmine = require("./redmine.coffee")

module.exports = (robot) ->
  redmine = new Redmine process.env.HUBOT_REDMINE_BASE_URL, process.env.HUBOT_REDMINE_TOKEN

  # Robot link me <issue>
  robot.respond /link me (?:issue )?(?:#)?(\d+)/i, (msg) ->
    id = msg.match[1]
    msg.reply "#{redmine.url}/issues/#{id}"

  # Robot set <issue> to <percent>% ["comments"]
  robot.respond /set (?:issue )?(?:#)?(\d+) to (\d{1,3})%?(?: "?([^"]+)"?)?/i, (msg) ->
    [id, percent, notes] = msg.match[1..3]
    percent = parseInt percent

    if notes?
      notes = "#{msg.message.user.name}: #{userComments}"
    else
      notes = "Ratio set by: #{msg.message.user.name}"

    attributes =
      "notes": notes
      "done_ratio": percent

    redmine.Issue(id).update attributes, (err, data, status) ->
      if status == 200
        msg.reply "Set ##{id} to #{percent}%"
      else
        msg.reply "Update failed! (#{err})"

  # Robot add <hours> hours to <issue_id> ["comments for the time tracking"]
  robot.respond /add (\d{1,2}) hours? to (?:issue )?(?:#)?(\d+)(?: "?([^"]+)"?)?/i, (msg) ->
    [hours, id, userComments] = msg.match[1..3]
    hours = parseInt hours

    if userComments?
      comments = "#{msg.message.user.name}: #{userComments}"
    else
      comments = "Time logged by: #{msg.message.user.name}"

    attributes =
      "issue_id": id
      "hours": hours
      "comments": comments

    redmine.TimeEntry(null).create attributes, (error, data, status) ->
      if status == 201
        msg.reply "Your time was logged"
      else
        msg.reply "Nothing could be logged. Make sure RedMine has a default activity set for time tracking. (Settings -> Enumerations -> Activities)"

  # Robot show <my|user's> [redmine] issues
  robot.respond /show (?:my|(\w+\'s)) (?:redmine )?issues/i, (msg) ->
    userMode = true
    firstName =
      if msg.match[1]?
        userMode = false
        msg.match[1].replace(/\'.+/, '')
      else
        msg.message.user.name.split(/\s/)[0]

    redmine.Users name:firstName, (err,data) ->
      unless data.total_count > 0
        msg.reply "Couldn't find any users with the name \"#{firstName}\""
        return false

      user = resolveUsers(firstName, data.users)[0]

      params =
        "assigned_to_id": user.id
        "limit": 25,
        "status_id": "open"
        "sort": "priority:desc",

      redmine.Issues params, (err, data) ->
        if err?
          msg.reply "Couldn't get a list of issues for you!"
        else
          _ = []

          if userMode
            _.push "You have #{data.total_count} issue(s)."
          else
            _.push "#{user.firstname} has #{data.total_count} issue(s)."

          for issue in data.issues
            do (issue) ->
              _.push "\n[#{issue.tracker.name} - #{issue.priority.name} - #{issue.status.name}] ##{issue.id}: #{issue.subject}"

          msg.reply _.join "\n"

  # Robot update <issue> with "<note>"
  robot.respond /update (?:issue )?(?:#)?(\d+)(?:\s*with\s*)?(?:[-:,])? (?:"?([^"]+)"?)/i, (msg) ->
    [id, note] = msg.match[1..2]

    attributes =
      "notes": "#{msg.message.user.name}: #{note}"

    redmine.Issue(id).update attributes, (err, data, status) ->
      unless data?
        if status == 404
          msg.reply "Issue ##{id} doesn't exist."
        else
          msg.reply "Couldn't update this issue, sorry :("
      else
        msg.reply "Done! Updated ##{id} with \"#{note}\""

  # Robot add issue to "<project>" [traker <id>] with "<subject>"
  robot.respond /add (?:issue )?(?:\s*to\s*)?(?:"?([^" ]+)"? )(?:tracker\s)?(\d+)?(?:\s*with\s*)(?:"?([^"]+)"?)/i, (msg) ->
    [project_id, tracker_id, subject] = msg.match[1..3]

    name = msg.message.user.name
    user = robot.brain.userForName name

    if user.room?
      name = user.id
    else
      name = user.privateChatJID.match(/\/(.*)$/)[1]

    due_date = new Date()
    due_date.setMonth(due_date.getMonth() + 1)

    attributes =
      "project_id": "#{project_id}"
      "subject": "#{subject}"
      "due_date": "#{formatDate due_date, 'yyyy-mm-dd'}"
      "assigned_to_id": 194 # backlog id
      "description": "Added through Hubot by #{name}"

    if tracker_id?
      attributes["tracker_id"] = "#{tracker_id}"

    redmine.Issue().add attributes, (err, data, status) ->
      if err?
        console.log err
      unless data?
        #if status == 404
        msg.reply "Couldn't update this issue, #{status} :("
      else
        issue = data.issue
        url = "#{redmine.url}/issues/#{issue.id}"
        msg.reply "Done! Added issue ##{issue.id} with \"#{subject}\""
        msg.reply "#{issue.tracker.name} ##{issue.id} (#{issue.project.name}): #{issue.subject} (#{issue.status.name}) [#{issue.priority.name}] #{url}"

  # Robot create project ["<name>" as] <id> [under <parent>]
  robot.respond /create project(?: "?([^"]*)"? as)? (\w+)(?: under (\w+))?/i, (msg) ->
    [name, id, parent] = msg.match[1..3]
    name ?= id

    options =
      name: name
      identifier: id
      enabled_module_names: [
        "issue_tracking"
        "time_tracking"
        "repository"
      ]
    resolve_parent_path = (projectid, cb, path=[]) ->
      redmine.Project projectid, (err, project, code) ->
        if err?
          return cb err
        unless project?
          return cb code
        path.unshift project.project.identifier
        if project.project.parent?.id?
          resolve_parent_path project.project.parent.id, cb, path
        else
          cb null, path.join('/')

    cb = (err, data, status) ->
      if err?
        console.log err
      unless data?
        #if status == 404
        msg.reply "Couldn't create this project, #{status} :("
      else
        project = data.project
        url = "#{redmine.url}/projects/#{project.identifier}"
        msg.reply "Done! created project #{project.name}"
        msg.reply "#{url}"
        resolve_parent_path data.project.identifier, (err,path) ->
          msg.reply "git url: ssh://git@redmine.inuits.eu:2223/#{path}.git"

    if parent?
      redmine.Project parent, (err, parent, code) ->
        options.parent_id = parent.project.id
        options.inherit_members = true
        redmine.post "/projects.json", {project: options}, cb
    else
      redmine.post "/projects.json", {project: options}, cb

  # Robot assign <issue> to <user> ["note to add with the assignment]
  robot.respond /assign (?:issue )?(?:#)?(\d+) to (\w+)(?: "?([^"]+)"?)?/i, (msg) ->
    [id, userName, note] = msg.match[1..3]

    redmine.Users name:userName, (err, data) ->
      unless data.total_count > 0
        msg.reply "Couldn't find any users with the name \"#{userName}\""
        return false

      # try to resolve the user using login/firstname -- take the first result (hacky)
      user = resolveUsers(userName, data.users)[0]

      attributes =
        "assigned_to_id": user.id

      # allow an optional note with the re-assign
      attributes["notes"] = "Assigned by #{msg.message.user.name}"
      attributes["notes"] += "#{msg.message.user.name}: #{note}" if note?

      # get our issue
      redmine.Issue(id).update attributes, (err, data, status) ->
        unless data?
          if status == 404
            msg.reply "Issue ##{id} doesn't exist."
          else
            msg.reply "There was an error assigning this issue."
        else
          msg.reply "Assigned ##{id} to #{user.firstname}."
          msg.send '/play trombone' if parseInt(id) == 3631

  # Robot redmine me <issue>
  robot.respond /(?:redmine|show|what is|whats|what's)(?: me)? (?:issue )?(?:#)?(\d+)/i, (msg) ->
    id = msg.match[1]

    params =
      "include": "journals"

    redmine.Issue(id).show params, (err, data, status) ->
      unless status == 200
        msg.reply "Issue ##{id} doesn't exist."
        return false

      issue = data.issue

      _ = []
      _.push "\n[#{issue.project.name} - #{issue.priority.name}] #{issue.tracker.name} ##{issue.id} (#{issue.status.name})"
      _.push "Assigned: #{issue.assigned_to?.name ? 'Nobody'} (opened by #{issue.author.name})"
      if issue.status.name.toLowerCase() != 'new'
         _.push "Progress: #{issue.done_ratio}% (#{issue.spent_hours} hours)"
      _.push "Subject: #{issue.subject}"
      _.push "\n#{issue.description}"

      # journals
      _.push "\n" + Array(10).join('-') + '8<' + Array(50).join('-') + "\n"
      for journal in issue.journals
        do (journal) ->
          if journal.notes? and journal.notes != ""
            date = formatDate journal.created_on, 'mm/dd/yyyy (hh:ii ap)'
            _.push "#{journal.user.name} on #{date}:"
            _.push "    #{journal.notes}\n"

      msg.reply _.join "\n"


  # hubot issue search [all] <keyword> - searches for issues on redmine. Gives you the first 5 found. unless all is present, hubot only looks for open tickets.
  robot.respond /issue\s+search\s+(all)?\s*(.*)/i, (msg) ->
    all = msg.match[1] == "all"
    keyword = msg.match[2].trim()

    msg.envelope.user.type = 'direct'

    params =
      "f[]": ["subject"]
      "op[subject]": "~"
      "v[subject][]": keyword
      "limit": 5

    unless all
      # &f[]=status_id&op[status_id]=o
      params["f[]"].push("status_id")
      params["op[status_id]"] = "o"

    message = ["\n"]
    redmine.Issues params, (err, data, status) ->
      unless status == 200
        msg.reply "Query for issues failed."
        return

      issues = data.issues
      for issue in issues
        url = "#{redmine.url}/issues/#{issue.id}"
        message.push "Subject: #{issue.subject}"
        message.push "[#{issue.project.name} - #{issue.priority.name}] #{issue.tracker.name} ##{issue.id} (#{issue.status.name})"
        message.push "Assigned: #{issue.assigned_to?.name ? 'Nobody'} (#{url})"
        message.push ""

      if issues.length == 0
        msg.reply "Found no issues with keyword: #{keyword}."
      else
        msg.reply message.join("\n")


  # Listens to #NNNN and gives ticket info
  robot.hear /.*(?:redmine|show|bug|issue|task|close|fix|see|feature).*(#(\d+)).*/, (msg) ->
    id = msg.match[1].replace /#/, ""

    ignoredUsers = process.env.HUBOT_REDMINE_IGNORED_USERS or ""

    #Ignore cetain users, like Redmine plugins
    if msg.message.user.name in ignoredUsers.split(',')
      return

    if isNaN(id)
      return

    params = []

    redmine.Issue(id).show params, (err, data, status) ->
      unless status == 200
        # Issue not found, don't say anything
        return false

      issue = data.issue

      url = "#{redmine.url}/issues/#{id}"
      msg.send "#{issue.tracker.name} ##{issue.id} (#{issue.project.name}): #{issue.subject} (#{issue.status.name}) [#{issue.priority.name}] #{url}"

# simple ghetto fab date formatter this should definitely be replaced, but didn't want to
# introduce dependencies this early
#
# dateStamp - any string that can initialize a date
# fmt - format string that may use the following elements
#       mm - month
#       dd - day
#       yyyy - full year
#       hh - hours
#       ii - minutes
#       ss - seconds
#       ap - am / pm
#
# returns the formatted date
formatDate = (dateStamp, fmt = 'mm/dd/yyyy at hh:ii ap') ->
  d = new Date(dateStamp)

  # split up the date
  [m,d,y,h,i,s,ap] =
    [d.getMonth() + 1, d.getDate(), d.getFullYear(), d.getHours(), d.getMinutes(), d.getSeconds(), 'AM']

  # leadig 0s
  m = "0#{m}" if m < 10
  d = "0#{d}" if d < 10
  i = "0#{i}" if i < 10
  s = "0#{s}" if s < 10

  # adjust hours
  if h > 12
    h = h - 12
    ap = "PM"

  # ghetto fab!
  fmt
    .replace(/mm/, m)
    .replace(/dd/, d)
    .replace(/yyyy/, y)
    .replace(/hh/, h)
    .replace(/ii/, i)
    .replace(/ss/, s)
    .replace(/ap/, ap)

# tries to resolve ambiguous users by matching login or firstname
# redmine's user search is pretty broad (using login/name/email/etc.) so
# we're trying to just pull it in a bit and get a single user
#
# name - this should be the name you're trying to match
# data - this is the array of users from redmine
#
# returns an array with a single user, or the original array if nothing matched
resolveUsers = (name, data) ->
    name = name.toLowerCase();

    # try matching login
    found = data.filter (user) -> user.login.toLowerCase() == name
    return found if found.length == 1

    # try first name
    found = data.filter (user) -> user.firstname.toLowerCase() == name
    return found if found.length == 1

    # give up
    data
