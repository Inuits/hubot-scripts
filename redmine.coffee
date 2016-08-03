

if process.env.HUBOT_REDMINE_SSL?
  HTTP = require('https')
else
  HTTP = require('http')

URL = require('url')
QUERY = require('querystring')

# Redmine API Mapping
# This isn't 100% complete, but its the basics for what we would need in campfire
class Redmine
  constructor: (url, token) ->
    @url = url
    @token = token

  Users: (params, callback) ->
    @get "/users.json", params, callback

  User: (id) ->

    show: (callback) =>
      @get "/users/#{id}.json", {}, callback

  Projects: (params, callback) ->
    @get "/projects.json", params, callback

  Project: (identifier, callback) ->
    @get "/projects/#{QUERY.escape(identifier)}.json", {}, callback

  Issues: (params, callback) ->
    @get "/issues.json", params, callback

  Issue: (id) ->

    show: (params, callback) =>
      @get "/issues/#{id}.json", params, callback

    update: (attributes, callback) =>
      @put "/issues/#{id}.json", {issue: attributes}, callback

    add: (attributes, callback) =>
      @Project attributes.project_id, (err, project, code) =>
        attributes.project_id = project.project.id
        @post "/issues.json", {issue: attributes}, callback

  TimeEntry: (id = null) ->

    create: (attributes, callback) =>
      @post "/time_entries.json", {time_entry: attributes}, callback

  # Private: do a GET request against the API
  get: (path, params, callback) ->
    path = "#{path}?#{QUERY.stringify params}" if params?
    @request "GET", path, null, callback

  # Private: do a POST request against the API
  post: (path, body, callback) ->
    @request "POST", path, body, callback

  # Private: do a PUT request against the API
  put: (path, body, callback) ->
    @request "PUT", path, body, callback

  # Private: Perform a request against the redmine REST API
  # from the campfire adapter :)
  request: (method, path, body, callback) ->
    headers =
      "Content-Type": "application/json"
      "X-Redmine-API-Key": @token

    endpoint = URL.parse(@url)
    pathname = endpoint.pathname.replace /^\/$/, ''

    options =
      "host"   : endpoint.hostname
      "port"   : endpoint.port
      "path"   : "#{pathname}#{path}"
      "method" : method
      "headers": headers

    if method in ["POST", "PUT"]
      if typeof(body) isnt "string"
        body = JSON.stringify body

      options.headers["Content-Length"] = body.length

    request = HTTP.request options, (response) ->
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", ->
        switch
          when response.statusCode < 300
            try
              callback null, JSON.parse(data), response.statusCode
            catch err
              callback null, (data or { }), response.statusCode
          when response.statusCode == 401
            throw new Error "401: Authentication failed."
          else
            console.error "Code: #{response.statusCode}"
            callback null, null, response.statusCode

      response.on "error", (err) ->
        console.error "Redmine response error: #{err}"
        callback err, null, response.statusCode

    if method in ["POST", "PUT"]
      request.end(body, 'binary')
    else
      request.end()

    request.on "error", (err) ->
      console.error "Redmine request error: #{err}"
      callback err, null, 0

module.exports = Redmine
