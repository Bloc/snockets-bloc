Snockets = require '../lib/snockets'
src = '../test/assets'
snockets = new Snockets({src})

testSuite =
  'Independent JS files have no dependencies': (test) ->
    snockets.scan 'b.js', (err) ->
      throw err if err
      test.ok snockets.depGraph.map['b.js']
      test.deepEqual snockets.depGraph.getChain('b.js'), []
      test.done()

  'Single-step dependencies are correctly recorded': (test) ->
    snockets.scan 'a.coffee', (err) ->
      throw err if err
      test.deepEqual snockets.depGraph.getChain('a.coffee'), ['b.js']
      test.done()

  'Dependencies with multiple extensions are accepted': (test) ->
    snockets.scan 'testing.js', (err) ->
      throw err if err
      test.deepEqual snockets.depGraph.getChain('testing.js'), ['1.2.3.coffee']
      test.done()

  'Chained dependencies are correctly recorded': (test) ->
    snockets.scan 'z.coffee', (err) ->
      throw err if err
      test.deepEqual snockets.depGraph.getChain('z.coffee'), ['x.coffee', 'y.js']
      test.done()

  'Dependency cycles cause no errors during scanning': (test) ->
    snockets.scan 'yin.js', (err) ->
      throw err if err
      test.throws -> snockets.depGraph.getChain('yin.js')
      test.throws -> snockets.depGraph.getChain('yang.coffee')
      test.done()

  'require_tree works for same directory': (test) ->
    snockets.scan 'branch/center.coffee', (err) ->
      throw err if err
      chain = snockets.depGraph.getChain('branch/center.coffee')
      test.deepEqual chain, ['branch/edge.coffee', 'branch/periphery.js']
      test.done()

  'require_tree works for nested directories': (test) ->
    snockets.scan 'fellowship.js', (err) ->
      throw err if err
      chain = snockets.depGraph.getChain('fellowship.js')
      test.deepEqual chain, ['middleEarth/legolas.coffee', 'middleEarth/shire/bilbo.js', 'middleEarth/shire/frodo.coffee']
      test.done()

  'getCompiledChain returns correct .js filenames and code': (test) ->
    snockets.getCompiledChain 'z.coffee', (err, chain) ->
      throw err if err
      test.deepEqual chain, [
        {filename: 'x.js', js: '(function() {\n  "Double rainbow\\nSO INTENSE";\n}).call(this);\n'}
        {filename: 'y.js', js: '//= require x'}
        {filename: 'z.js', js: '(function() {\n\n}).call(this);\n'}
      ]
      test.done()

  'getConcatenation returns correct raw JS code': (test) ->
    snockets.getConcatenation 'z.coffee', (err, js) ->
      throw err if err
      test.equal js, """
        (function() {\n  "Double rainbow\\nSO INTENSE";\n}).call(this);\n
        //= require x
        (function() {\n\n}).call(this);\n
      """
      test.done()

  'getConcatenation returns correct minified JS code': (test) ->
    snockets.getConcatenation 'z.coffee', minify: true, (err, js) ->
      throw err if err
      test.equal js, """
        (function(){"Double rainbow\\nSO INTENSE"}).call(this),function(){}.call(this)
      """
      test.done()

# Every test runs both synchronously and asynchronously.
for name, func of testSuite
  do (func) ->
    exports[name] = (test) ->
      snockets.options.async = true;  func(test)
    exports[name + ' (sync)'] = (test) ->
      snockets.options.async = false; func(test)