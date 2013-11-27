(function() {
  var DIRECTIVE, DUMMY, DepGraph, EXPLICIT_PATH, HEADER, HoldingQueue, Snockets, compilers, fs, getUrlPath, jsExts, minify, parseDirectives, path, sourceMapCat, stripExt, timeEq, _, _ref, _ref1,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    __slice = [].slice;

  DepGraph = require('dep-graph');

  fs = require('fs');

  path = require('path');

  _ = require('underscore');

  DUMMY = 'dummy';

  _ref = require('./util'), parseDirectives = _ref.parseDirectives, HoldingQueue = _ref.HoldingQueue, timeEq = _ref.timeEq, getUrlPath = _ref.getUrlPath, sourceMapCat = _ref.sourceMapCat, EXPLICIT_PATH = _ref.EXPLICIT_PATH, DIRECTIVE = _ref.DIRECTIVE, HEADER = _ref.HEADER;

  _ref1 = require('./compilers'), compilers = _ref1.compilers, jsExts = _ref1.jsExts, stripExt = _ref1.stripExt;

  minify = require('./minification').minify;

  Snockets = (function() {
    function Snockets(options) {
      var _base, _base1, _base2, _base3, _base4, _base5;
      this.options = options != null ? options : {};
      this._requireTreeStatement = __bind(this._requireTreeStatement, this);
      this._requireStatement = __bind(this._requireStatement, this);
      if ((_base = this.options).path_env == null) {
        _base.path_env = [];
      }
      if ((_base1 = this.options).target == null) {
        _base1.target = null;
      }
      if ((_base2 = this.options).staticRoot == null) {
        _base2.staticRoot = null;
      }
      if ((_base3 = this.options).staticRootUrl == null) {
        _base3.staticRootUrl = '/';
      }
      if ((_base4 = this.options).src == null) {
        _base4.src = '.';
      }
      if ((_base5 = this.options).async == null) {
        _base5.async = true;
      }
      this.cache = {};
      this.concatCache = {};
      this.depGraph = new DepGraph;
    }

    Snockets.prototype.scan = function(entryFileName) {
      return this._buildDependenceGraph(entryFileName);
    };

    Snockets.prototype.getChain = function() {
      return this.depGraph.getChain(DUMMY);
    };

    Snockets.prototype._requireStatement = function(cwd, relPath) {
      var depFilePath;
      relPath = stripExt(relPath);
      depFilePath = this._findMatchingFile(cwd, relPath);
      return depFilePath;
    };

    Snockets.prototype._isJSFilename = function(filename) {
      return filename.match(/\.js$/) || filename.match(/\.coffee$/);
    };

    Snockets.prototype._hiddenFile = function(filename) {
      return filename[0] === '.';
    };

    Snockets.prototype._requireTreeStatement = function(basePath) {
      var dependentFiles, item, itemPath, newFiles, nonHiddenFiles, x, _i, _j, _len, _len1;
      nonHiddenFiles = _(this.readDirectory(basePath)).reject(this._hiddenFile);
      dependentFiles = [];
      for (_i = 0, _len = nonHiddenFiles.length; _i < _len; _i++) {
        item = nonHiddenFiles[_i];
        itemPath = path.normalize(path.join(basePath, item));
        if (this._isFile(itemPath)) {
          if (this._isJSFilename(itemPath)) {
            dependentFiles.push(itemPath);
          }
        } else {
          newFiles = this._requireTreeStatement(itemPath);
          for (_j = 0, _len1 = newFiles.length; _j < _len1; _j++) {
            x = newFiles[_j];
            dependentFiles.push(x);
          }
        }
      }
      return dependentFiles;
    };

    Snockets.prototype._extractRequiredFilenames = function(cwd, fileContent) {
      var command, directives, i, postRequiredFiles, relPaths, requiredFiles, splitPointFound, words, _i, _ref2;
      directives = parseDirectives(fileContent);
      splitPointFound = false;
      requiredFiles = [];
      postRequiredFiles = [];
      for (i = _i = 0, _ref2 = directives.length; 0 <= _ref2 ? _i < _ref2 : _i > _ref2; i = 0 <= _ref2 ? ++_i : --_i) {
        words = directives[i].replace(/['"]/g, '').split(/\s+/);
        command = words[0], relPaths = 2 <= words.length ? __slice.call(words, 1) : [];
        if (command === "require_self") {
          splitPointFound = true;
        } else if (splitPointFound) {
          postRequiredFiles.push(directives[i]);
        } else {
          requiredFiles.push(directives[i]);
        }
      }
      return {
        pre: this._traceDirectives(cwd, requiredFiles),
        post: this._traceDirectives(cwd, postRequiredFiles)
      };
    };

    Snockets.prototype._traceDirectives = function(cwd, directives) {
      var command, computedDirectory, directive, fileName, fileNames, relPath, relPaths, requiredFiles, words, x, _i, _j, _k, _l, _len, _len1, _len2, _len3;
      requiredFiles = [];
      for (_i = 0, _len = directives.length; _i < _len; _i++) {
        directive = directives[_i];
        words = directive.replace(/['"]/g, '').split(/\s+/);
        command = words[0], relPaths = 2 <= words.length ? __slice.call(words, 1) : [];
        switch (command) {
          case 'require':
            for (_j = 0, _len1 = relPaths.length; _j < _len1; _j++) {
              relPath = relPaths[_j];
              fileName = this._requireStatement(cwd, relPath);
              requiredFiles.push(fileName);
            }
            break;
          case 'require_tree':
            for (_k = 0, _len2 = relPaths.length; _k < _len2; _k++) {
              relPath = relPaths[_k];
              computedDirectory = path.normalize(path.join(cwd, relPath));
              fileNames = this._requireTreeStatement(computedDirectory);
              for (_l = 0, _len3 = fileNames.length; _l < _len3; _l++) {
                x = fileNames[_l];
                requiredFiles.push(x);
              }
            }
        }
      }
      return requiredFiles;
    };

    Snockets.prototype._buildDependenceGraph = function(entryFile) {
      var dependencies, excludes, filename, postDependence, preDependence, q, x, _i, _len, _results;
      q = [entryFile];
      excludes = {};
      _results = [];
      while (q.length > 0) {
        filename = q.shift();
        if (excludes[filename] != null) {
          continue;
        }
        excludes[filename] = 1;
        dependencies = this._extractFilenameDependencies(filename);
        preDependence = dependencies.pre;
        if (preDependence.length > 0) {
          this._addFileDependencies(filename, preDependence);
          for (_i = 0, _len = preDependence.length; _i < _len; _i++) {
            x = preDependence[_i];
            q.push(x);
          }
        }
        postDependence = dependencies.post;
        if (postDependence.length > 0) {
          this._addFileDependencies(filename, postDependence, true);
          _results.push((function() {
            var _j, _len1, _results1;
            _results1 = [];
            for (_j = 0, _len1 = postDependence.length; _j < _len1; _j++) {
              x = postDependence[_j];
              _results1.push(q.push(x));
            }
            return _results1;
          })());
        } else {
          _results.push(void 0);
        }
      }
      return _results;
    };

    Snockets.prototype._addFileDependencies = function(filename, dependencies, reverse) {
      var dependence, _i, _len;
      if (reverse == null) {
        reverse = false;
      }
      for (_i = 0, _len = dependencies.length; _i < _len; _i++) {
        dependence = dependencies[_i];
        if (reverse) {
          if (dependence !== filename) {
            this.depGraph.add(dependence, filename);
          }
        } else {
          if (dependence !== filename) {
            this.depGraph.add(filename, dependence);
          }
        }
        this.depGraph.add(DUMMY, dependence);
      }
      return this.depGraph.add(DUMMY, filename);
    };

    Snockets.prototype._extractFilenameDependencies = function(filename) {
      var content, cwd;
      cwd = path.dirname(filename);
      content = this._readFile(filename);
      return this._extractRequiredFilenames(cwd, content);
    };

    Snockets.prototype._convertDirectivesToFilenames = function(cwd, directives) {
      var directive, filepaths, _i, _len;
      filepaths = [];
      for (_i = 0, _len = directives.length; _i < _len; _i++) {
        directive = directives[_i];
        filepaths.push(this._findMatchingFile(cwd, directive));
      }
      return filepaths;
    };

    Snockets.prototype._isFile = function(filePath) {
      var e;
      try {
        return this._stat(filePath).isFile();
      } catch (_error) {
        e = _error;
        return false;
      }
    };

    Snockets.prototype._findMatchingFile = function(cwd, filename) {
      var altBasePath, altFile, altPath, cwdFile, cwdPath, _i, _len, _ref2;
      cwdPath = path.normalize(path.join(cwd, filename));
      cwdFile = this._tryJSFileExtensions(cwdPath);
      if (cwdFile !== null) {
        return cwdFile;
      }
      _ref2 = this.options.path_env;
      for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
        altBasePath = _ref2[_i];
        altPath = path.normalize(path.join(altBasePath, filename));
        altFile = this._tryJSFileExtensions(altPath);
        if (altFile != null) {
          return altFile;
        }
      }
      throw new Error("File not found: '" + filename + "'");
    };

    Snockets.prototype._tryJSFileExtensions = function(filepath) {
      var alt, ext, _i, _len, _ref2;
      _ref2 = ['.js', '.coffee', '.js.coffee'];
      for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
        ext = _ref2[_i];
        alt = filepath + ext;
        if (this._isFile(alt)) {
          return alt;
        }
      }
      return null;
    };

    Snockets.prototype.readDirectory = function(dir) {
      return fs.readdirSync(dir);
    };

    Snockets.prototype._stat = function(filePath) {
      return fs.statSync(filePath);
    };

    Snockets.prototype._readFile = function(filePath) {
      return fs.readFileSync(filePath, {
        encoding: 'utf8'
      });
    };

    return Snockets;

  })();

  module.exports = Snockets;

  module.exports.compilers = compilers;

}).call(this);
