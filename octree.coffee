class Octree
    constructor: ( opts ) ->
        @extend this, {
            parent: null
            o: [ 0.0, 0.0, 0.0 ]
            size: 1
            threshold: 10
            octantIdx: 0
            depth: 0
        }, opts

        @_threshold = @threshold
        @hSize = @size / 2
        @octants = []
        @nodes = []
        @nodesLen = 0
        @branchesLen = 0
        @updateAabb()
        @depth = if @isRoot() then 0 else @parent.depth + 1

    extend: -> # obj, defaults, config
        for i in [ 1 ... arguments.length ]
            for key of arguments[i]
                if arguments[i].hasOwnProperty key
                    arguments[0][key] = arguments[i][key]
        return arguments[0]

    stats: =>
        stats = { total_depth: 0 }
        @sink ( branch ) =>
            path = []
            branch.bubble ( branch ) => path.push( branch.octantIdx )
            path.reverse()
            selector = stats
            for idx in path
                if !selector[ idx ]? then selector[ idx ] = {}
                selector = selector[ idx ]
            selector.path_to_here = path.join '.'
            if branch.depth > stats.total_depth then stats.total_depth = branch.depth
            selector.branch_depth = branch.depth
            selector.bloat_here = branch._threshold - branch.threshold
            selector.len_nodes_here = branch.nodes.length
            selector.len_nodes_branch = branch.nodesLen
            selector.len_branches = branch.branchesLen
        return stats

    updateAabb: =>
        @aabb = [
            [ @o[0] - @hSize, @o[1] - @hSize, @o[2] - @hSize ],
            [ @o[0] + @hSize, @o[1] + @hSize, @o[2] + @hSize ]
        ]

    isRoot: => return !@parent?

    isEmpty: => return @nodes.length is 0

    isFull: => return @nodes.length >= @_threshold

    isLeaf: => return @octants.length is 0

    isBranchEmpty: =>
        flag = true
        @sink ( tree ) => if !tree.isEmpty() then flag = false
        return flag

    root: =>
        root = this
        @bubble ( tree ) => root = tree
        return root

    getOctantByVec: ( vec ) =>
        idx = 0
        if vec[0] >= @o[0] then idx += 4
        if vec[1] >= @o[1] then idx += 2
        if vec[2] >= @o[2] then idx += 1
        return @octants[ idx ]

    getOctantByAabb: ( aabb ) =>
        if @containsAabbAabb( @octants[0].aabb, aabb ) then return 0
        if @containsAabbAabb( @octants[1].aabb, aabb ) then return 1
        if @containsAabbAabb( @octants[2].aabb, aabb ) then return 2
        if @containsAabbAabb( @octants[3].aabb, aabb ) then return 3
        if @containsAabbAabb( @octants[4].aabb, aabb ) then return 4
        if @containsAabbAabb( @octants[5].aabb, aabb ) then return 5
        if @containsAabbAabb( @octants[6].aabb, aabb ) then return 6
        if @containsAabbAabb( @octants[7].aabb, aabb ) then return 7
        return -1 # overlapping / split over multiple octants

    insert: ( node ) =>
        if node.location? or node.position? or node.centroid?
            if node.location? then accessor = 'location'
            if node.position? then accessor = 'position'
            if node.centroid? then accessor = 'centroid'
            isBounding = false
        if node.bounds? or node.boundingBox? or node.aabb?
            if node.bounds? then accessor = 'bounds'
            if node.boundingBox? then accessor = 'boundingBox'
            if node.aabb? then accessor = 'aabb'
            isBounding = true
        if !accessor?
            console.log '[ octree.js ] Unable to insert node: no detectable positional or bounding information.', node
        else
            nodeToInsert = {
                data: node
                accessor: accessor
                isBounding: isBounding
                geometry: ( -> return this.data[ accessor ] )
            }
            if nodeToInsert.isBounding
                isContained = @containsAabbAabb @aabb, nodeToInsert.geometry()
            else
                isContained = @intersectAabbVec @aabb, nodeToInsert.geometry()
            if isContained
                @_insert nodeToInsert
            else
                console.log '[ octree.js ] Node out of bounds or not completely within octree bounds:', this, node
        return node

    _insert: ( node ) =>
        if @isLeaf()
            @_insertHere node
        else
            if node.isBounding
                idx = @getOctantByAabb node.geometry()
                if idx < 0 # overlaps octants
                    if @isFull() then @_threshold++
                    @_insertHere node
                else
                    @octants[ idx ]._insert node
            else
                @getOctantByVec( node.geometry() )._insert node

    _insertHere: ( node ) =>
        if @isFull()
            @subdivide()
            @_insert node
            #@reload()
        else
            @bubble ( branch ) => branch.nodesLen++
            node.parent = this
            @nodes.push node
            if node.onInsert?
                if !node.hasBeenInserted
                    node.hasBeenInserted = true
                    node.data.onInsert this
                else if node.onUpdate?
                    node.data.onUpdate this

    remove: ( node ) =>
        if !node? then return false
        if node.parent? and node.parent instanceof Octree
            node.parent.nodes.splice node.parent.nodes.indexOf( node ), 1
            node.parent.reload()
            return node.data
        else
            @sink ( tree ) =>
                removed = false
                for checkNode in tree.nodes
                    if checkNode.data is node
                        tree.nodes.splice tree.nodes.indexOf( checkNode ), 1
                        tree.reload()
                        removed = true
                        break
                if removed then return node
        return false

    subdivide: =>
        @bubble ( branch ) => branch.branchesLen += 8
        ### in relation to root
        child    0 1 2 3 4 5 6 7
            x    - - - - + + + +
            y    - - + + - - + +
            z    - + - + - + - +
        ###
        p = [ @o[0] + @hSize/2, @o[1] + @hSize/2, @o[2] + @hSize/2 ]
        n = [ @o[0] - @hSize/2, @o[1] - @hSize/2, @o[2] - @hSize/2 ]
        @octants[0] = new Octree { parent: this, o: [ n[0], n[1], n[2] ], size: @hSize, threshold: @threshold, octantIdx: 0 }
        @octants[1] = new Octree { parent: this, o: [ n[0], n[1], p[2] ], size: @hSize, threshold: @threshold, octantIdx: 1 }
        @octants[2] = new Octree { parent: this, o: [ n[0], p[1], n[2] ], size: @hSize, threshold: @threshold, octantIdx: 2 }
        @octants[3] = new Octree { parent: this, o: [ n[0], p[1], p[2] ], size: @hSize, threshold: @threshold, octantIdx: 3 }
        @octants[4] = new Octree { parent: this, o: [ p[0], n[1], n[2] ], size: @hSize, threshold: @threshold, octantIdx: 4 }
        @octants[5] = new Octree { parent: this, o: [ p[0], n[1], p[2] ], size: @hSize, threshold: @threshold, octantIdx: 5 }
        @octants[6] = new Octree { parent: this, o: [ p[0], p[1], n[2] ], size: @hSize, threshold: @threshold, octantIdx: 6 }
        @octants[7] = new Octree { parent: this, o: [ p[0], p[1], p[2] ], size: @hSize, threshold: @threshold, octantIdx: 7 }

    reload: =>
        reinsertNode = ( node ) =>
            if node?
                @bubble ( branch ) => branch.nodesLen--
                if @_threshold > @threshold then @_threshold--
                @_insert node
                reinsertNode @nodes.pop()
        reinsertNode @nodes.pop()
        #@root().trim()

    bubble: ( fn ) =>
        fn this
        if !@isRoot() then @parent.bubble fn

    sink: ( fn ) =>
        fn this
        tree.sink fn for tree in @octants

    trim: =>
        @sink ( tree ) =>
            if tree.isBranchEmpty()
                tree.octants = []
                @bubble ( branch ) => branch.branchesLen -= tree.branchesLen

    aabbIntersects: ( aabb1, aabb2 ) =>
        dot = ( a, b ) -> return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
        bases = [
            [ 1, 0, 0 ],
            [ 0, 1, 0 ],
            [ 0, 0, 1 ]
        ]
        for axis in [ 0 ... 3 ]
            flag = true
            tCalcs = [
                dot( [ aabb2[0][0], aabb2[0][1], aabb2[0][2] ], bases[ axis ] ),
                dot( [ aabb2[1][0], aabb2[0][1], aabb2[0][2] ], bases[ axis ] ),
                dot( [ aabb2[0][0], aabb2[1][1], aabb2[0][2] ], bases[ axis ] ),
                dot( [ aabb2[1][0], aabb2[1][1], aabb2[0][2] ], bases[ axis ] ),
                dot( [ aabb2[0][0], aabb2[0][1], aabb2[1][2] ], bases[ axis ] ),
                dot( [ aabb2[1][0], aabb2[0][1], aabb2[1][2] ], bases[ axis ] ),
                dot( [ aabb2[0][0], aabb2[1][1], aabb2[1][2] ], bases[ axis ] ),
                dot( [ aabb2[1][0], aabb2[1][1], aabb2[1][2] ], bases[ axis ] )
            ]
            for t in tCalcs
                if !tmin? then tmin = t
                if !tmax? then tmax = t
                if t < tmin then tmin = t
                if t > tmax then tmax = t
            o1 = dot aabb1[0], bases[ axis ]
            o2 = dot aabb1[1], bases[ axis ]
            if tmin > o2 or tmax < o1
                flag = false
                break
        return flag

    intersectAabbVec: ( aabb, vec ) =>
        return vec[0] <= aabb[1][0] and
            vec[1] <= aabb[1][1] and
            vec[2] <= aabb[1][2] and
            vec[0] >= aabb[0][0] and
            vec[1] >= aabb[0][1] and
            vec[2] >= aabb[0][2]

    intersectSphereVec: ( s, vec ) =>
        diff = [ s[0] - vec[0], s[1] - vec[1], s[2] - vec[2] ]
        mag = diff[0] * diff[0] + diff[1] * diff[1] + diff[2] * diff[2]
        rad = s[3] * s[3]
        return mag <= rad

    intersectAabbAabb: ( aabb1, aabb2 ) =>
        if @intersectAabbVec( aabb1, aabb2[0] ) or @intersectAabbVec( aabb1, aabb2[1] )
            return true
        return @aabbIntersects( aabb1, aabb2 ) or @aabbIntersects( aabb2, aabb1 )

    containsAabbAabb: ( aabb, tAabb ) =>
        return ( aabb[0][0] <= tAabb[0][0] ) and ( aabb[1][0] >= tAabb[1][0] ) and
            ( aabb[0][1] <= tAabb[0][1] ) and ( aabb[1][1] >= tAabb[1][1] ) and
            ( aabb[0][2] <= tAabb[0][2] ) and ( aabb[1][2] >= tAabb[1][2] )

    intersectSphereSphere: ( s1, s2 ) =>
        diff = [ s2[0] - s1[0], s2[1] - s1[1], s2[2] - s1[2] ]
        mag = diff[0] * diff[0] + diff[1] * diff[1] + diff[2] * diff[2]
        rad = s2[3] + s1[3]
        return mag <= rad * rad

    intersectAabbSphere: ( aabb, sphere ) =>
        # Arvo's algorithm "solid box - solid sphere"
        # http://tog.acm.org/resources/GraphicsGems/gems/BoxSphere.c
        dmin = 0
        for i in [ 0 ... 3 ] # three dimensions
            if sphere[i] < aabb[0][i] then dmin += Math.pow ( sphere[i] - aabb[0][i] ), 2
            if sphere[i] > aabb[1][i] then dmin += Math.pow ( sphere[i] - aabb[1][i] ), 2
        return dmin <= Math.pow sphere[3], 2

    frustumToObb: ( frustum ) =>
        # ?
        # if = mat4.invert mat4.create(), frustum
        # obb = mat4.mul mat4.create(), frustum, if
        # ?

    intersectAabbFrustum: ( aabb, frustum ) =>
        # this should check a bounding box of the frustum first, then if there's an intersection
        # check with this algorithm
        dot = ( a, b ) -> return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
        mag = ( vec ) -> return Math.sqrt vec[0] * vec[0] + vec[1] * vec[1] + vec[2] * vec[2]
        vmax = [ 0, 0, 0 ]
        vmin = [ 0, 0, 0 ]
        flag = false

        for plane in frustum
            # x
            if plane[1][0] > 0
                vmin[0] = aabb[0][0]
                vmax[0] = aabb[1][0]
            else
                vmin[0] = aabb[1][0]
                vmax[0] = aabb[0][0]
            # y
            if plane[1][1] > 0
                vmin[1] = aabb[0][1]
                vmax[1] = aabb[1][1]
            else
                vmin[1] = aabb[1][1]
                vmax[1] = aabb[0][1]
            # z
            if plane[1][2] > 0
                vmin[2] = aabb[0][2]
                vmax[2] = aabb[1][2]
            else
                vmin[2] = aabb[1][2]
                vmax[2] = aabb[0][2]

            planeD = mag plane[0]
            # if dot( plane[1], vmin ) + planeD > 0 # aabb is outside of plane definition
            if dot( plane[1], vmax ) + planeD >= 0 # intersection
                flag = true
                break
        return flag # if code doesn't break from intersection, then the aabb is completely within the frustum

    mapAll: ( fn ) =>
        allNodes = []
        @sink ( tree ) => allNodes.push fn( node.data ) for node in tree.nodes
        return allNodes

    collectAll: ( property ) =>
        allNodes = []
        if property?
            @sink ( tree ) => allNodes.push node.data[ property ] for node in tree.nodes
        else
            @sink ( tree ) => allNodes.push node.data for node in tree.nodes
        return allNodes

    collectAllPreSorted: ( sortFn, property ) =>
        nodes = @collectAll().sort sortFn
        if property?
            tmpArr = []
            idx = 0
            while idx <= nodes.length - 1
                tmpArr.push nodes[ idx ][ property ]
                idx++
            return tmpArr
        else
            return nodes

    collectAllPostSorted: ( sortFn, property ) => return @collectAll( property ).sort sortFn

    streamAll: ( callback, property ) =>
        if property?
            if property is '__raw'
                @sink ( tree ) => callback node for node in tree.nodes
            else
                @sink ( tree ) => callback node.data[ property ] for node in tree.nodes
        else
            @sink ( tree ) => callback node.data for node in tree.nodes
        return undefined

    removeAllStream: ( callback ) =>
        popfn = ( tree, fn ) =>
            node = tree.nodes.pop()
            if node?
                fn node.data
                @bubble ( branch ) => branch.nodesLen -= 1
                popfn tree, fn
        @sink ( tree ) =>
            popfn tree, callback
        @trim()
        return undefined

    random: =>
        allNodes = @collectAll()
        return allNodes[ Math.floor Math.random() * allNodes.length ]

    ifIntersectsAabb: ( aabb, callback ) =>
        if @intersectAabbAabb @aabb, aabb
            for node in @nodes
                if node.isBounding
                    if @insertectAabbAabb aabb, node.geometry() then callback node.data
                else
                    if @intersectAabbVec aabb, node.geometry() then callback node.data
            tree.ifIntersectsAabb aabb, callback for tree in @octants

    ifIntersectsSphere: ( s, callback ) =>
        if @intersectAabbSphere @aabb, s
            for node in @nodes
                if node.isBounding
                    if @intersectAabbSphere node.geometry(), s then callback node.data
                else
                    if @intersectSphereVec s, node.geometry() then callback node.data
            tree.ifIntersectsSphere s, callback for tree in @octants

    queryByAabb: ( aabb ) =>
        matchedNodes = []
        @ifIntersectsAabb aabb, ( node ) => matchedNodes.push node
        return matchedNodes

    queryBySphere: ( s ) =>
        matchedNodes = []
        @ifIntersectsSphere s, ( node ) => matchedNodes.push node
        return matchedNodes

    streamBySphere: ( s, callback ) =>
        @ifIntersectsSphere s, ( node ) => callback node
        return undefined


    ###
        USER FUNCTIONS AND ARGUMENT SIGNATURES
    ###
    # === MANAGEMENT === These 
    #   constructor -> Object options
    #       Defaults: {
    #           parent: null
    #           o: [ 0.0, 0.0, 0.0 ]
    #           size: 1
    #           threshold: 10
    #           octantIdx: 0
    #           depth: 0
    #       }
    #       Returns: Octree octree
    #
    #   insert -> Object node
    #       Insert will attempt to read location data from the node,
    #           preferring bounding information to vector information
    #           with the following priorities (least to greatest):
    #           - location
    #           | position
    #           | centroid
    #           | bounds
    #           | boundingBox
    #           V aabb
    #       The Octree will deal with bounds vs. vector information accordingly
    #           and is able to handle both simultaneously and for all queries.
    #       Returns: Object node
    #
    #   root ->
    #       #root() will return the root octree from and branch
    #       Returns: Octree root
    #
    #   stats ->
    #       #stats() is useful for debugging. It will return a tree, where each branch is the corresponding branch
    #           in the octree identified by its octant index. The root has `total_depth`, and each branch has the
    #           following information:
    #                   bloat_here    The amount of nodes that would overlap if pushed lower down the graph. Overlapping cases violate the threshold constraint
    #                 branch_depth    Depth at this branch
    #                 len_branches    Total amount of branches contained in and under this branch to total depth of graph
    #             len_nodes_branch    Total amount of nodes contained in and under this branch to total depth of graph
    #               len_nodes_here    Nodes contained in this branch (should be less than or equal to threshold, unless there is bloating, then it should equal the bloat plus threshold)
    #                 path_to_here    Path is a period delimited string of octant indices to and including this branch (ie. "0" is the root, and "0.1" is octant at index one of the root)
    #       Returns: Object object
    #
    # === ITERATORS === These operate on the structure of the octree
    #   bubble -> Function( Function fn )
    #       Executes `fn` on receiving octree, then up parent structure
    #         until execution stops at the root.
    #       Returns: undefined
    #
    #   sink -> Function( Function fn )
    #       Executes `fn` on the receiving octree, then to all children recursively
    #         through the total depth of the graph
    #       Returns: undefined
    #
    # === QUERIES === These return nodes
    #   mapAll -> Function( Object node )
    #       Returns: Array[ Returned objects from callback ]
    #
    #   collectAll -> { String property }
    #       Returns: Array[ All nodes, unless property is specified, then all data from nodes at that accessor ]
    #
    #   collectAllPreSorted -> Function sortFn {, String property }
    #       Sort function acts on nodes
    #       Returns: Array[ See notes in #collectAll(), but sorted by #Array.sort( sortFn ) ]
    #
    #   collectAllPostSorted -> Function sortFn {, String property }
    #       Sort function acts on whatever is returned from #collectAll() with the property paramater
    #       Returns: Array[ See notes in #collectAll(), but sorted by #Array.sort( sortFn ) ]
    #
    #   streamAll -> Function( Object node ){, String property }
    #       Callback is called per node, unless property is specified,
    #         then callback is called per node with the data at that accessor
    #       Returns: undefined
    #
    #   removeAllStream -> Function( Object node )
    #       Callback is called per node at the same time that node is removed
    #           from the octree
    #       Returns: undefined
    #
    #   random ->
    #       Returns: Object node
    #
    #   queryByAabb ->  3x2  Array [ x  x ]
    #                              | y  y |
    #                              [ z  z ]
    #       Returns: Array[ Nodes intersecting sphere ]
    #
    #   queryBySphere ->  1x4  Array [ x  y  z  r ]
    #       Returns: Array[ Nodes intersecting axis-aligned bounding box ]
    #
    #   streamBySphere -> 1x4 Array [ x y z r ], Function( Object node ) callback
    #       Callback is called per node intersecting sphere
    #       Returns: undefined

octreeTest = {
    test: ->
        if !window? then window = {}
        window.o = new Octree {
            o: [ 0, 0, 0 ]
            size: 2
            threshold: 1
        }
        testNodes = [
            {
                name: 'center node in octant 0'
                aabb: [[ -0.55, -0.55, -0.55 ], [ -0.45, -0.45, -0.45 ]]
            },
            {
                name: 'center node in octant 1'
                aabb: [[ -0.55, -0.55, 0.45 ], [ -0.45, -0.45, 0.55 ]]
            },
            {
                name: 'center node in octant 2'
                aabb: [[ -0.55, 0.45, -0.55 ], [ -0.45, 0.55, -0.45 ]]
            },
            {
                name: 'center node in octant 3'
                aabb: [[ -0.55, 0.45, 0.45 ], [ -0.45, 0.55, 0.55 ]]
            },
            {
                name: 'center node in octant 3.0/1'
                aabb: [[ -0.8, 0.2, 0.45 ], [ -0.7, 0.3, 0.55 ]]
            },
            {
                name: 'center node in octant 3.0'
                aabb: [[ -0.8, 0.2, 0.2 ], [ -0.7, 0.3, 0.3 ]]
            },
            {
                name: 'center node in octant 3.1'
                aabb: [[ -0.8, 0.2, 0.7 ], [ -0.7, 0.3, 0.8 ]]
            },
            {
                name: 'center node in octant 3.2'
                aabb: [[ -0.8, 0.7, 0.2 ], [ -0.7, 0.8, 0.3 ]]
            },
            {
                name: 'center node in octant 3.3'
                aabb: [[ -0.8, 0.7, 0.7 ], [ -0.7, 0.8, 0.8 ]]
            },
            {
                name: 'center node in octant 3.4'
                aabb: [[ -0.3, 0.2, 0.2 ], [ -0.2, 0.3, 0.3 ]]
            },
            {
                name: 'center node in octant 3.5'
                aabb: [[ -0.3, 0.2, 0.7 ], [ -0.2, 0.3, 0.8 ]]
            },
            {
                name: 'center node in octant 3.6'
                aabb: [[ -0.3, 0.7, 0.2 ], [ -0.2, 0.8, 0.3 ]]
            },
            {
                name: 'center node in octant 3.7'
                aabb: [[ -0.3, 0.7, 0.7 ], [ -0.2, 0.8, 0.8 ]]
            },
            {
                name: 'center node in octant 4'
                aabb: [[ 0.45, -0.55, -0.55 ], [ 0.55, -0.45, -0.45 ]]
            },
            {
                name: 'center node in octant 5'
                aabb: [[ 0.45, -0.55, 0.45 ], [ 0.55, -0.45, 0.55 ]]
            },
            {
                name: 'center node in octant 6'
                aabb: [[ 0.45, 0.45, -0.55 ], [ 0.55, 0.55, -0.45 ]]
            },
            {
                name: 'center node in octant 7'
                aabb: [[ 0.45, 0.45, 0.45 ], [ 0.55, 0.55, 0.55 ]]
            }
        ]
        window.o.insert tn for tn in testNodes
        return window.o

    prepareBuffers: ( o ) ->
        totalDepth = o.stats().total_depth
        octants = []
        o.sink ( branch ) =>
            aabb = branch.aabb
            back_bottom_left   = aabb[0]
            back_bottom_right  = [ aabb[1][0], aabb[0][1], aabb[0][2] ]
            back_top_left      = [ aabb[0][0], aabb[1][1], aabb[0][2] ]
            back_top_right     = [ aabb[1][0], aabb[1][1], aabb[0][2] ]
            front_bottom_left  = [ aabb[0][0], aabb[0][1], aabb[1][2] ]
            front_bottom_right = [ aabb[1][0], aabb[0][1], aabb[1][2] ]
            front_top_left     = [ aabb[0][0], aabb[1][1], aabb[1][2] ]
            front_top_right    = aabb[1]
            octants.push {
                opacity: ((totalDepth - branch.depth) + 1) / (totalDepth + 1)
                vertices: [
                    # front
                    front_bottom_left,
                    front_bottom_right,

                    front_bottom_right,
                    front_top_right,

                    front_top_right,
                    front_top_left,

                    front_top_left,
                    front_bottom_left

                    # back
                    back_bottom_left,
                    back_bottom_right,

                    back_bottom_right,
                    back_top_right,

                    back_top_right,
                    back_top_left,

                    back_top_left,
                    back_bottom_left

                    # top
                    back_top_left,
                    back_top_right,

                    back_top_right,
                    front_top_right,

                    front_top_right,
                    front_top_left,

                    front_top_left,
                    back_top_left

                    # bottom
                    back_bottom_left,
                    back_bottom_right,

                    back_bottom_right,
                    front_bottom_right,

                    front_bottom_right,
                    front_bottom_left,

                    front_bottom_left,
                    back_bottom_left

                    # right
                    back_bottom_right,
                    back_top_right,

                    back_top_right,
                    front_top_right,

                    front_top_right,
                    front_bottom_right,

                    front_bottom_right,
                    back_bottom_right

                    # left
                    back_bottom_left,
                    back_top_left,

                    back_top_left,
                    front_top_left,

                    front_top_left,
                    front_bottom_left,

                    front_bottom_left,
                    back_bottom_left
                ]
            }
        return {
            octants: octants
            nodes: o.collectAll 'aabb'
        }
}

exports.Octree = Octree
exports.octreeTest = octreeTest
