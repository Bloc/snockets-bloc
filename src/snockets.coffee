# [snockets](http://github.com/TrevorBurnham/snockets)

DepGraph = require 'dep-graph'

CoffeeScript = require 'coffee-script'
fs           = require 'fs'
path         = require 'path'
uglify       = require 'uglify-js'
_            = require 'underscore'

module.exports = class Snockets
  constructor: (@options = {}) ->
    @options.src ?= '.'
    @options.async ?= true
    @cache = {}
    @depGraph = new DepGraph

  # ## Public methods

  scan: (filePath, flags, callback) ->
    if typeof flags is 'function'
      callback = flags; flags = {}
    flags ?= {}
    flags.async ?= @options.async

    @updateDirectives filePath, flags, (err) =>
      if err
        if callback then callback err else throw err
      callback? null, @depGraph
      @depGraph

  getCompiledChain: (filePath, flags, callback) ->
    if typeof flags is 'function'
      callback = flags; flags = {}
    flags ?= {}
    flags.async ?= @options.async

    @updateDirectives filePath, flags, (err) =>
      if err
        if callback then callback err else throw err
      try
        chain = @depGraph.getChain filePath
      catch e
        if callback then callback e else throw e

      compiledChain = for link in chain.concat filePath
        o = {}
        if @compileFile link
          o.filename = stripExt(link) + '.js'
        else
          o.filename = link
        o.js = @cache[link].js.toString 'utf8'
        o

      callback? null, compiledChain
      compiledChain

  getConcatenation: (filePath, flags, callback) ->
    if typeof flags is 'function'
      callback = flags; flags = {}
    flags ?= {}
    flags.async ?= @options.async

    @updateDirectives filePath, flags, (err) =>
      if err
        if callback then callback err else throw err
      try
        chain = @depGraph.getChain filePath
      catch e
        if callback then callback e else throw e

      concatenation = (for link in chain.concat filePath
        @compileFile link
        @cache[link].js.toString 'utf8'
      ).join '\n'

      if flags.minify then concatenation = minify concatenation

      callback? null, concatenation
      concatenation

  # ## Internal methods

  # Interprets the directives from the given file to update `@depGraph`.
  updateDirectives: (filePath, flags, excludes..., callback) ->
    return callback() if filePath in excludes
    excludes.push filePath

    depList = []
    q = new HoldingQueue
      task: (depPath, next) =>
        if depPath is filePath
          err = new Error("Script tries to require itself: #{filePath}")
          return callback err
        depList.push depPath
        @updateDirectives depPath, flags, excludes..., (err) ->
          return callback err if err
          next()
      onComplete: =>
        @depGraph.map[filePath] = depList
        callback()

    require = (relPath) =>
      q.waitFor relName = stripExt relPath
      if relName.match EXPLICIT_PATH
        depPath = relName + '.js'
        q.perform relName, depPath
      else
        depName = path.join path.dirname(filePath), relName
        @findMatchingFile depName, flags, (err, depPath) ->
          return callback err if err
          q.perform relName, depPath

    requireTree = (relPath) =>
      q.waitFor relPath
      dirName = path.join path.dirname((filePath)), relPath
      @readdir @absPath(dirName), flags, (err, items) =>
        return callback err if err
        q.unwaitFor relPath
        for item in items
          itemPath = path.join(dirName, item)
          continue if @absPath(itemPath) is @absPath(filePath)
          q.waitFor itemPath
          do (itemPath) =>
            @stat @absPath(itemPath), flags, (err, stats) =>
              return callback err if err
              if stats.isFile()
                if path.extname(itemPath) in jsExts()
                  q.perform itemPath, itemPath
                else
                  return q.unwaitFor itemPath
              else if stats.isDirectory()
                requireTree itemPath

    @readFile filePath, flags, (err) =>
      return callback err if err
      for directive in parseDirectives(@cache[filePath].data.toString 'utf8')
        words = directive.replace(/['"]/g, '').split /\s+/
        [command, relPaths...] = words

        switch command
          when 'require'
            require relPath for relPath in relPaths
          when 'require_tree'
            requireTree relPath for relPath in relPaths

      q.finalize()

  # Searches for a file with the given name (no extension, e.g. `'foo/bar'`)
  findMatchingFile: (filename, flags, callback) ->
    tryFiles = (filePaths) =>
      for filePath in filePaths
        if stripExt(@absPath filePath) is @absPath(filename)
          callback null, filePath
          return true

    return if tryFiles _.keys @cache
    @readdir path.dirname(@absPath filename), flags, (err, files) =>
      return callback err if err
      return if tryFiles files
      callback new Error("File not found: '#{filename}'")

  # Wrapper around fs.readdir or fs.readdirSync, depending on flags.async.
  readdir: (dir, flags, callback) ->
    if flags.async
      fs.readdir @absPath(dir), callback
    else
      try
        files = fs.readdirSync @absPath(dir)
        callback null, files
      catch e
        callback e

  # Wrapper around fs.stat or fs.statSync, depending on flags.async.
  stat: (filePath, flags, callback) ->
    if flags.async
      fs.stat @absPath(filePath), callback
    else
      try
        stats = fs.statSync @absPath(filePath)
        callback null, stats
      catch e
        callback e

  # Reads a file's data and timestamp into the cache.
  readFile: (filePath, flags, callback) ->
    @stat filePath, flags, (err, stats) =>
      return callback err if err
      return callback() if timeEq @cache[filePath]?.mtime, stats.mtime
      if flags.async
          fs.readFile @absPath(filePath), (err, data) =>
            return callback err if err
            @cache[filePath] = {mtime: stats.mtime, data}
            callback()
      else
        try
          data = fs.readFileSync @absPath(filePath)
          @cache[filePath] = {mtime: stats.mtime, data}
          callback()
        catch e
          callback e

  compileFile: (filePath) ->
    if (ext = path.extname filePath) is '.js'
      @cache[filePath].js = @cache[filePath].data
      false
    else
      src = @cache[filePath].data.toString 'utf8'
      js = compilers[ext[1..]].compileSync @absPath(filePath), src
      @cache[filePath].js = new Buffer(js)
      true

  absPath: (relPath) ->
    if relPath.match EXPLICIT_PATH
      relPath
    else
      path.join process.cwd(), @options.src, relPath

# ## Compilers

module.exports.compilers = compilers =
  coffee:
    match: /\.js$/
    compileSync: (sourcePath, source) ->
      CoffeeScript.compile source, {filename: sourcePath}

# ## Regexes

EXPLICIT_PATH = /^\/|^\.|:/

HEADER = ///
(?:
  (\#\#\# .* \#\#\#\n?) |
  (// .* \n?) |
  (\# .* \n?)
)+
///

DIRECTIVE = ///
^[\W] *= \s* (\w+.*?) (\*\\/)?$
///gm

# ## Utility functions

class HoldingQueue
  constructor: ({@task, @onComplete}) ->
    @holdKeys = []
  waitFor: (key) ->
    @holdKeys.push key
  unwaitFor: (key) ->
    @holdKeys = _.without @holdKeys, key
  perform: (key, args...) ->
    @task args..., => @unwaitFor key
  finalize: ->
    if @holdKeys.length is 0
      @onComplete()
    else
      h = setInterval (=>
        if @holdKeys.length is 0
          @onComplete()
          clearInterval h
      ), 10

parseDirectives = (code) ->
  return [] unless match = HEADER.exec(code)
  header = match[0]
  match[1] while match = DIRECTIVE.exec header

stripExt = (filePath) ->
  if path.extname(filePath) in jsExts()
    filePath[0...filePath.lastIndexOf('.')]
  else
    filePath

jsExts = ->
  (".#{ext}" for ext of compilers).concat '.js'

minify = (js) ->
  jsp = uglify.parser
  pro = uglify.uglify
  ast = jsp.parse js
  ast = pro.ast_mangle ast
  ast = pro.ast_squeeze ast
  pro.gen_code ast

timeEq = (date1, date2) ->
  date1? and date2? and date1.getTime() is date2.getTime()