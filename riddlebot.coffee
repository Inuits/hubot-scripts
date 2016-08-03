# Description:
#   The master of conundrums itself, the riddlebot will stump you with only the most difficult riddles.
#
# Commands:
#   riddle me this? - Gives the user a riddle.
#   riddle me that? - Gives the answer to the last riddle given.
#   riddle me done! [user's answer] - Determines whether the user's answer is correct or not.
#   hubot daily riddle - Gives you the daily riddle
#   hubot daily riddle solve <answer> - Checks if your answer is correct
#
# Author:
#   HerrPfister
#   Joey

fs = require('fs')
path = require('path')
riddlesJSON = require('./riddles.json')
riddles = riddlesJSON.randomRiddles
dailyRiddles = riddlesJSON.dailyRiddles

module.exports = (robot) ->
  robot.hear /riddle me this[?]/i, (res) ->
    index = Math.floor(Math.random() * riddles.length)
    riddle = riddles[index].riddle
    answer = riddles[index].answer

    robot.brain.set('answer', answer)
    res.reply('It\'s time to get smart! ' + riddle)


  robot.hear /riddle me that[?]/i, (res) ->
    correctAnswer = robot.brain.get('answer')
    res.reply('Giving up already? Well I should have seen that coming. Here is the answer to that riddle: ' + correctAnswer + ".")


  robot.hear /riddle me done[!]\s*(.*)/i, (res) ->
    userAnswer = res.match[1].toLowerCase()
    correctAnswer = robot.brain.get('answer')

    if correctAnswer?
      correctAnswer = correctAnswer.toLowerCase()
    else
      res.reply "I don't have a riddle queued"
      return

    #if !userAnswer || correctAnswer.indexOf(userAnswer) == -1
    if !userAnswer || userAnswer.toLowerCase().trim().search(correctAnswer) < 0
      res.reply('Wrong! It doesn\'t suprise me that I out smarted you.')
    else
      robot.brain.remove('answer')
      res.reply('Well would you look at that! You do have the ability to think. ' +
        'Alas! Don\'t get too comfortable, because the next one will be much harder.')


  # hubot daily riddle - Gives you the daily riddle
  robot.respond /daily riddle\s*$/i, (res) ->
    index = getDailyRiddleIndex()
    riddle = dailyRiddles[index].riddle
    solver = getFirstSolver(index)
    message = "The riddle of the day is:\n" + riddle
    if solver?
      message += "\n\nIt was first solved by: #{solver}"
    else
      message += "\n\nBe the first to solve it!"

    res.send message


  # hubot daily riddle solve <answer> - Checks if your answer is correct
  robot.respond /daily riddle solve (.*)/i, (res) ->
    index = getDailyRiddleIndex()
    correctAnswer = dailyRiddles[index].answer
    solver = getFirstSolver(index)
    userAnswer = res.match[1]

    if userAnswer.toLowerCase().trim().search(correctAnswer.toLowerCase()) >= 0
      message = "That is correct!"
      unless solver?
        message += "\nYou are the first one to solve the daily riddle"
        name = res.message.user.name
        setFirstSolver(index, name)
    else
      message = "Too bad, try again."

    res.reply message

  getFirstSolver = (index) ->
    solver = robot.brain.get("dailyRiddleSolver")
    console.log solver
    if solver? and solver.index == index
      return solver.name
    return undefined

  setFirstSolver = (index, solver) ->
    robot.brain.set("dailyRiddleSolver", {index: index, name: solver})


getDailyRiddleIndex = () ->
    dayNumber = Math.floor(new Date().getTime() / (1000 * 60 * 60 * 24))
    return dayNumber % dailyRiddles.length
