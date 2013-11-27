Snockets = require '../lib/snockets'
path     = require 'path'
src      = 'spec/assets'


describe 'Snockets', ->

  snockets = null

  testFilepath = (partialPath) -> return path.normalize(path.join(src, partialPath))

  beforeEach ->
    snockets = new Snockets { path_env: ["spec/remote_assets", "spec/second_remote_assets"]}

  afterEach ->
    snockets = null

  it "creates a zero length dependence for a file with no dependencies", ->
    testFile = testFilepath('b.js')
    snockets.scan testFile
    depGraph = snockets.depGraph
    expect(depGraph.getChain(testFile)).toEqual []

  it "finds a single dependence in the same working directory", ->
    testFile = testFilepath('a.coffee')
    snockets.scan testFile
    depGraph = snockets.depGraph
    expect(depGraph.getChain(testFile)).toEqual ['spec/assets/b.js']

  it 'creates dependencies for all javascript file extensions', ->
    testFile = testFilepath('testing.js')
    expectedArray = (testFilepath(x) for x in ['1.2.3.coffee', '4.5.6.js', '7.8.9.js.coffee'])
    snockets.scan testFile
    expect(snockets.depGraph.getChain(testFile)).toEqual expectedArray

  it 'correctly creates dependencies for files with dependencies in same subdirectory', ->
    testFile = testFilepath('song/loveAndMarriage.js')
    expectedArray = (testFilepath(x) for x in ['song/horseAndCarriage.coffee'])
    snockets.scan testFile
    expect(snockets.depGraph.getChain(testFile)).toEqual expectedArray

  it 'allows for multiple dependencies in one require directive', ->
    testFile = testFilepath('poly.coffee')
    expectedArray = (testFilepath(x) for x in ['b.js', 'x.coffee'])
    snockets.scan testFile
    expect(snockets.depGraph.getChain(testFile)).toEqual expectedArray

  it 'creates the correct dependencies for indirect dependencies', ->
    testFile = testFilepath('z.coffee')
    expectedArray = (testFilepath(x) for x in ['x.coffee', 'y.js'])
    snockets.scan testFile
    expect(snockets.depGraph.getChain(testFile)).toEqual expectedArray

  it "cyclic include doesn't throw an error during scanning", ->
    yinFile = testFilepath('yin.js')
    yangFile = testFilepath('yang.coffee')

    snockets.scan(yinFile)
    expect( ->
      snockets.depGraph.getChain(yinFile)
    ).toThrow()
    expect( ->
      snockets.depGraph.getChain(yangFile)
    ).toThrow()

  it 'includes all files in a requrire_tree directory', ->
    expectedArray = (testFilepath(x) for x in ['branch/edge.coffee', 'branch/periphery.js', 'branch/subbranch/leaf.js'].sort())

    testFile = testFilepath('branch/center.coffee')
    snockets.scan testFile
    chain = snockets.depGraph.getChain(testFile)
    expect(chain.sort()).toEqual expectedArray

  it 'allows for use of relative paths in requires', ->
    testFile =  testFilepath('first/syblingFolder.js')
    expectedArray =  [testFilepath('sybling/sybling.js')]
    snockets.scan testFile
    chain = snockets.depGraph.getChain(testFile)
    expect(chain).toEqual expectedArray

  it 'properly builds require_tree dependencies within nested directories', ->
    expectedChain = (testFilepath(x) for x in ['middleEarth/legolas.coffee', 'middleEarth/shire/bilbo.js', 'middleEarth/shire/frodo.coffee'].sort())

    testFile = testFilepath('fellowship.js')
    snockets.scan testFile
    chain = snockets.depGraph.getChain(testFile)
    expect(chain.sort()).toEqual expectedChain

  it 'require_tree works for redundant directories', ->
    expectedChain = (testFilepath(x) for x in ['middleEarth/shire/bilbo.js', 'middleEarth/shire/frodo.coffee', 'middleEarth/legolas.coffee'].sort())
    testFile = testFilepath('trilogy.coffee')
    snockets.scan testFile
    chain = snockets.depGraph.getChain(testFile)
    expect(chain.sort()).toEqual expectedChain

  it "correctly requires files that are in an alternate path", ->
    testFile = testFilepath('file_with_remote.coffee')
    expectedChain = ['spec/remote_assets/remote_file.coffee', 'spec/second_remote_assets/second_remote_file.coffee'].sort()
    snockets.scan testFile
    chain = snockets.depGraph.getChain(testFile)
    expect(chain.sort()).toEqual expectedChain

  it "correctly handles require_self", ->
    testFile = testFilepath('file_with_self.coffee')
    expectedChain = [testFile, 'spec/assets/b.js']
    snockets.scan testFile
    chain = snockets.getChain()
    expect(chain).toEqual expectedChain

  it "replaces require_self when using getChain", ->
    testFile = testFilepath('file_with_self.coffee')
    expectedChain = ['spec/assets/file_with_self.coffee', 'spec/assets/b.js']
    snockets.scan testFile
    chain = snockets.getChain()
    expect(chain).toEqual expectedChain

  it "appends the entry file when require_self is not present", ->
    testFile = testFilepath('file_with_self.coffee')
    expectedChain = ['spec/assets/file_with_self.coffee', 'spec/assets/b.js']
    snockets.scan testFile
    chain = snockets.getChain()
    expect(chain).toEqual expectedChain

  it "handles multiple require selfs", ->
    testFile = testFilepath('multiple_self.js')
    expectedChain = ['spec/assets/multiple_self.js', 'spec/assets/multiple/another_require_self.js', 'spec/assets/b.js']
    snockets.scan testFile
    chain = snockets.getChain()
    expect(chain).toEqual expectedChain




