# [snockets](http://github.com/pthrasher/snockets)

DepGraph = require 'dep-graph'
fs           = require 'fs'
path         = require 'path'
_            = require 'underscore'


DUMMY = 'dummy'

{ parseDirectives, HoldingQueue,
    timeEq, getUrlPath,
    sourceMapCat, EXPLICIT_PATH,
    DIRECTIVE, HEADER } = require './util'
{ compilers, jsExts, stripExt } = require './compilers'
{ minify }              = require './minification'


class Snockets
  constructor: (@options = {}) ->
    @options.path_env ?= []
    @options.target ?= null
    @options.staticRoot ?= null
    @options.staticRootUrl ?= '/'
    @options.src ?= '.'
    @options.async ?= true
    @cache = {}
    @concatCache = {}
    @depGraph = new DepGraph

  # ## Public methods
  scan: (entryFileName) ->
    @_buildDependenceGraph(entryFileName)

  getChain: ->
    return @depGraph.getChain(DUMMY)

 ## Internal methods
  _requireStatement: (cwd, relPath) =>
    relPath = stripExt(relPath)
    depFilePath = @_findMatchingFile(cwd, relPath)
    return depFilePath

  _isJSFilename: (filename) ->
    (filename.match(/\.js$/) || filename.match(/\.coffee$/))

  _hiddenFile: (filename) ->
    filename[0] == '.'


  _requireTreeStatement: (basePath) =>
    nonHiddenFiles = _(@readDirectory(basePath)).reject(@_hiddenFile)

    dependentFiles = []

    for item in nonHiddenFiles
      itemPath = path.normalize(path.join(basePath, item))
      if @_isFile(itemPath)
        dependentFiles.push(itemPath) if @_isJSFilename(itemPath)
      else
        newFiles = @_requireTreeStatement(itemPath)
        dependentFiles.push(x) for x in newFiles

    return dependentFiles

  _extractRequiredFilenames: (cwd, fileContent) ->
    directives = parseDirectives(fileContent)
    splitPointFound = false
    requiredFiles = []
    postRequiredFiles = []
    for i in [0...directives.length]
      words = directives[i].replace(/['"]/g, '').split /\s+/
      [command, relPaths...] = words
      if command == "require_self"
        splitPointFound = true
      else if splitPointFound
        postRequiredFiles.push(directives[i])
      else
        requiredFiles.push(directives[i])

    return {pre: @_traceDirectives(cwd, requiredFiles), post: @_traceDirectives(cwd, postRequiredFiles) }


  _traceDirectives: (cwd, directives) ->
    requiredFiles = []
    for directive in directives
      words = directive.replace(/['"]/g, '').split /\s+/
      [command, relPaths...] = words

      switch command
        when 'require'
          for relPath in relPaths
            fileName = @_requireStatement(cwd, relPath)
            requiredFiles.push(fileName)
        when 'require_tree'
          for relPath in relPaths
            computedDirectory = path.normalize(path.join(cwd, relPath))
            fileNames = @_requireTreeStatement(computedDirectory)
            requiredFiles.push x for x in fileNames

    return requiredFiles

  _buildDependenceGraph: (entryFile) ->
    q = [entryFile]
    excludes = { }

    while q.length > 0
      filename = q.shift()
      continue if excludes[filename]?
      excludes[filename] = 1
      dependencies = @_extractFilenameDependencies(filename)
      preDependence = dependencies.pre
      if preDependence.length > 0
        @_addFileDependencies(filename, preDependence)
        # For some reason q.concat(dependencies) doesn't work.
        q.push(x) for x in preDependence

      postDependence = dependencies.post
      if postDependence.length > 0
        @_addFileDependencies(filename, postDependence, true)
        # For some reason q.concat(dependencies) doesn't work.
        q.push(x) for x in postDependence


  _addFileDependencies: (filename, dependencies, reverse=false) ->
    for dependence in dependencies
      if reverse
        @depGraph.add(dependence, filename) unless dependence == filename
      else
        @depGraph.add(filename, dependence) unless dependence == filename
      @depGraph.add(DUMMY, dependence)
    @depGraph.add(DUMMY, filename)

  _extractFilenameDependencies: (filename) ->
    cwd = path.dirname(filename)
    content = @_readFile(filename)
    return @_extractRequiredFilenames(cwd, content)

  _convertDirectivesToFilenames: (cwd, directives) ->
    filepaths = []
    for directive in directives
      filepaths.push @_findMatchingFile(cwd, directive)

    return filepaths

  _isFile: (filePath) ->
    try
      return @_stat(filePath).isFile()
    catch e
      return false

  # Searches for a file with the given name (no extension, e.g. `'foo/bar'`)
  # Given a partial path e.g. "angular" (lib file), "utilties/credit_card" (file in subdirectory), or "utilities" (directory)
  #  - Need to look at the search path directories in priority order File's Directory -> @path[0] -> @path[1]
  _findMatchingFile: (cwd, filename) ->
    cwdPath = path.normalize(path.join(cwd, filename))
    cwdFile = @_tryJSFileExtensions(cwdPath)
    return cwdFile if cwdFile != null

    for altBasePath in @options.path_env
      altPath = path.normalize(path.join(altBasePath, filename))
      altFile = @_tryJSFileExtensions(altPath)
      return altFile if altFile?

    throw new Error("File not found: '#{filename}'")

  _tryJSFileExtensions: (filepath) ->
    for ext in ['.js', '.coffee', '.js.coffee']
      alt = filepath + ext
      return alt if @_isFile(alt)

    return null


  readDirectory: (dir) ->
    return fs.readdirSync dir

  _stat: (filePath) ->
    fs.statSync(filePath)

  _readFile: (filePath) ->
    return fs.readFileSync(filePath, {encoding: 'utf8'})

module.exports = Snockets
module.exports.compilers = compilers
