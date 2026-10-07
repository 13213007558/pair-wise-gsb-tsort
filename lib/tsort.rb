# frozen_string_literal: true

#--
# tsort.rb - provides a module for topological sorting and strongly connected components.
#++
#

#
# TSort implements topological sorting using Tarjan's algorithm for
# strongly connected components.
#
# TSort is designed to be able to be used with any object which can be
# interpreted as a directed graph.
#
# TSort requires two methods to interpret an object as a graph,
# tsort_each_node and tsort_each_child.
#
# * tsort_each_node is used to iterate for all nodes over a graph.
# * tsort_each_child is used to iterate for child nodes of a given node.
#
# The equality of nodes are defined by eql? and hash since
# TSort uses Hash internally.
#
# == A Simple Example
#
# The following example demonstrates how to mix the TSort module into an
# existing class (in this case, Hash). Here, we're treating each key in
# the hash as a node in the graph, and so we simply alias the required
# #tsort_each_node method to Hash's #each_key method. For each key in the
# hash, the associated value is an array of the node's child nodes. This
# choice in turn leads to our implementation of the required #tsort_each_child
# method, which fetches the array of child nodes and then iterates over that
# array using the user-supplied block.
#
#   require 'tsort'
#
#   class Hash
#     include TSort
#     alias tsort_each_node each_key
#     def tsort_each_child(node, &block)
#       fetch(node).each(&block)
#     end
#   end
#
#   {1=>[2, 3], 2=>[3], 3=>[], 4=>[]}.tsort
#   #=> [3, 2, 1, 4]
#
#   {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}.strongly_connected_components
#   #=> [[4], [2, 3], [1]]
#
# == A More Realistic Example
#
# A very simple `make' like tool can be implemented as follows:
#
#   require 'tsort'
#
#   class Make
#     def initialize
#       @dep = {}
#       @dep.default = []
#     end
#
#     def rule(outputs, inputs=[], &block)
#       triple = [outputs, inputs, block]
#       outputs.each {|f| @dep[f] = [triple]}
#       @dep[triple] = inputs
#     end
#
#     def build(target)
#       each_strongly_connected_component_from(target) {|ns|
#         if ns.length != 1
#           fs = ns.delete_if {|n| Array === n}
#           raise TSort::Cyclic.new("cyclic dependencies: #{fs.join ', '}")
#         end
#         n = ns.first
#         if Array === n
#           outputs, inputs, block = n
#           inputs_time = inputs.map {|f| File.mtime f}.max
#           begin
#             outputs_time = outputs.map {|f| File.mtime f}.min
#           rescue Errno::ENOENT
#             outputs_time = nil
#           end
#           if outputs_time == nil ||
#              inputs_time != nil && outputs_time <= inputs_time
#             sleep 1 if inputs_time != nil && inputs_time.to_i == Time.now.to_i
#             block.call
#           end
#         end
#       }
#     end
#
#     def tsort_each_child(node, &block)
#       @dep[node].each(&block)
#     end
#     include TSort
#   end
#
#   def command(arg)
#     print arg, "\n"
#     system arg
#   end
#
#   m = Make.new
#   m.rule(%w[t1]) { command 'date > t1' }
#   m.rule(%w[t2]) { command 'date > t2' }
#   m.rule(%w[t3]) { command 'date > t3' }
#   m.rule(%w[t4], %w[t1 t3]) { command 'cat t1 t3 > t4' }
#   m.rule(%w[t5], %w[t4 t2]) { command 'cat t4 t2 > t5' }
#   m.build('t5')
#
# == Bugs
#
# * 'tsort.rb' is wrong name because this library uses
#   Tarjan's algorithm for strongly connected components.
#   Although 'strongly_connected_components.rb' is correct but too long.
#
# == References
#
# R. E. Tarjan, "Depth First Search and Linear Graph Algorithms",
# <em>SIAM Journal on Computing</em>, Vol. 1, No. 2, pp. 146-160, June 1972.
#

module TSort

  # The version string.
  VERSION = "0.2.0"

  # A directed edge with an identity independent from its endpoints.
  # Two edges with the same source and target are still distinct when their
  # #id values differ, or when #id is +nil+.
  class DirectedEdge
    attr_reader :source, :target, :id

    def initialize(source, target, id=nil)
      @source = source
      @target = target
      @id = id
    end

    def ==(other)
      other.is_a?(DirectedEdge) &&
        source == other.source &&
        target == other.target &&
        id == other.id
    end
    alias eql? ==

    def hash
      [source, target, id].hash
    end

    def inspect
      "#<#{self.class}: #{source.inspect}->#{target.inspect} #{id.inspect}>"
    end
  end

  # A node or a composition in a two-terminal series-parallel decomposition.
  class Decomposition
    attr_reader :source, :target, :id, :uid

    def initialize(source, target, id=nil, uid: nil)
      @source = source
      @target = target
      @id = id
      @uid = uid
    end

    def each_node(&block)
      return enum_for(:each_node) unless block_given?
      yield source
      yield target
      nil
    end

    def each_edge(&block)
      return enum_for(:each_edge) unless block_given?
      yield self
      nil
    end

    def original_edges
      each_edge.to_a
    end

    def original_edge_ids
      original_edges.map(&:id)
    end

    def expand
      nodes = []
      each_node {|node| nodes << node unless nodes.include?(node) }
      Graph.new(nodes, each_edge.to_a)
    end

    def structural_equal?(other)
      self.class == other.class &&
        source == other.source &&
        target == other.target &&
        id == other.id
    end

    # An atomic edge in a decomposition tree.
    class Edge < Decomposition
      def ==(other)
        structural_equal?(other)
      end
      alias eql? ==

      def hash
        [self.class, source, target, id].hash
      end
    end

    # A series composition. The target of each child equals the source of
    # the following child.
    class Series < Decomposition
      attr_reader :children

      def self.build(source, target, children, uid: nil)
        flattened = children.flat_map do |child|
          child.is_a?(Series) ? child.children : [child]
        end
        new(source, target, flattened, uid: uid)
      end

      def initialize(source, target, children, uid: nil)
        super(source, target, nil, uid: uid)
        @children = children.dup
      end

      def each_node(&block)
        return enum_for(:each_node) unless block_given?
        seen = {}
        yield_node = proc do |node|
          unless seen[node]
            seen[node] = true
            yield node
          end
        end
        yield_node.call(source)
        children.each do |child|
          child.each_node(&yield_node)
        end
        yield_node.call(target)
        nil
      end

      def each_edge(&block)
        return enum_for(:each_edge) unless block_given?
        children.each {|child| child.each_edge(&block) }
        nil
      end

      def ==(other)
        structural_equal?(other) && children == other.children
      end
      alias eql? ==

      def hash
        [self.class, source, target, children].hash
      end
    end

    # A parallel composition. Every child has the same source and target.
    class Parallel < Decomposition
      attr_reader :children

      def self.build(source, target, children, uid: nil)
        flattened = children.flat_map do |child|
          child.is_a?(Parallel) ? child.children : [child]
        end
        new(source, target, flattened, uid: uid)
      end

      def initialize(source, target, children, uid: nil)
        super(source, target, nil, uid: uid)
        @children = children.dup
      end

      def each_node(&block)
        return enum_for(:each_node) unless block_given?
        seen = {}
        yield_node = proc do |node|
          unless seen[node]
            seen[node] = true
            yield node
          end
        end
        yield_node.call(source)
        children.each {|child| child.each_node(&yield_node) }
        yield_node.call(target)
        nil
      end

      def each_edge(&block)
        return enum_for(:each_edge) unless block_given?
        children.each {|child| child.each_edge(&block) }
        nil
      end

      def ==(other)
        structural_equal?(other) && children == other.children
      end
      alias eql? ==

      def hash
        [self.class, source, target, children].hash
      end
    end
  end

  # A directed graph represented as nodes and edge-like objects. Edges must
  # respond to #source, #target, and optionally #id.
  class Graph
    include TSort

    attr_reader :nodes, :edges, :all_nodes

    def initialize(nodes, edges=[], all_nodes=nodes)
      @nodes = nodes.dup
      @edges = edges.dup
      @all_nodes = all_nodes.dup
    end

    def add_node(node)
      unless @nodes.include?(node)
        @nodes << node
        @all_nodes << node unless @all_nodes.include?(node)
      end
      self
    end

    def add_edge(edge)
      @edges << edge
      self
    end

    def tsort_each_node(&block)
      @nodes.each(&block)
    end

    def tsort_each_edge(node, &block)
      @edges.each {|edge| yield edge if edge.source == node }
    end

    def tsort_each_child(node, &block)
      tsort_each_edge(node) {|edge| yield edge.target }
    end

    def isolated_nodes
      @nodes.select do |node|
        @edges.none? {|edge| edge.source == node || edge.target == node }
      end
    end

    def removed_nodes
      @all_nodes - @nodes
    end
  end

  # One series or parallel reduction made while recognizing a graph.
  class ReductionOperation
    attr_reader :type, :source, :target, :child_ids, :result_id

    def initialize(type, source, target, child_ids, result_id)
      @type = type
      @source = source
      @target = target
      @child_ids = child_ids
      @result_id = result_id
    end

    def to_h
      {
        type: type,
        source: source,
        target: target,
        child_ids: child_ids,
        result_id: result_id
      }
    end
  end

  # A replayable record of the original graph and the applied reductions.
  class Certificate
    attr_reader :source, :target, :nodes, :original_edges, :operations

    def initialize(source, target, nodes, original_edges, operations)
      @source = source
      @target = target
      @nodes = nodes
      @original_edges = original_edges
      @operations = operations
    end

    def replay
      active_nodes = {}
      @nodes.each {|node| active_nodes[node] = true }
      active_edges = {}

      @original_edges.each_with_index do |edge, index|
        uid = "edge-#{index}"
        next unless @nodes.include?(edge.source) &&
                    @nodes.include?(edge.target)
        active_edges[uid] = Decomposition::Edge.new(
          edge.source, edge.target, edge.id, uid: uid)
      end

      @operations.each do |operation|
        children = operation.child_ids.map {|id| active_edges.fetch(id) }
        children.each {|child| active_edges.delete(child.uid) }

        case operation.type
        when :parallel
          tree = Decomposition::Parallel.build(
            operation.source, operation.target, children,
            uid: operation.result_id)
        when :series
          incoming, outgoing = children
          unless incoming.target == outgoing.source
            raise "invalid series certificate: #{incoming.inspect} and #{outgoing.inspect}"
          end
          active_nodes[incoming.target] = false
          tree = Decomposition::Series.build(
            operation.source, operation.target, children,
            uid: operation.result_id)
        else
          raise "unknown certificate operation: #{operation.type.inspect}"
        end
        active_edges[operation.result_id] = tree
      end

      nodes = @nodes.select {|node| active_nodes[node] }
      Graph.new(nodes, active_edges.values, @nodes)
    end
  end

  # A diagnostic explaining why a graph or part of a graph cannot be part of
  # a clean two-terminal series-parallel decomposition.
  class Diagnostic
    attr_reader :code, :message, :node, :edge

    def initialize(code, message, node: nil, edge: nil)
      @code = code
      @message = message
      @node = node
      @edge = edge
    end

    def to_h
      result = {code: code, message: message}
      result[:node] = node unless node.nil?
      unless edge.nil?
        result[:edge] = {
          source: edge.source,
          target: edge.target,
          id: edge.id
        }
      end
      result
    end

    def to_s
      message
    end
  end

  # The successful or unsuccessful result of series-parallel recognition.
  class SeriesParallelResult
    attr_reader :source, :target, :tree, :residual_graph,
                :diagnostics, :certificate

    def initialize(source, target, tree, residual_graph, diagnostics, certificate)
      @source = source
      @target = target
      @tree = tree
      @residual_graph = residual_graph
      @diagnostics = diagnostics
      @certificate = certificate
    end

    def ok?
      !tree.nil?
    end
    alias decomposition tree

    def residual_edges
      residual_graph.edges
    end

    def replay
      certificate.replay
    end

    def verified?
      replayed = replay
      replayed.nodes == residual_graph.nodes &&
        replayed.edges == residual_graph.edges
    end
  end

  class SeriesParallelReducer # :nodoc:
    def self.run(source, target, each_node, each_edge)
      new(source, target, each_node, each_edge).run
    end

    def initialize(source, target, each_node, each_edge)
      @source = source
      @target = target
      @each_node = each_node
      @each_edge = each_edge
      @sequence = 0
    end

    def run
      nodes = []
      @each_node.call {|node| nodes << node unless nodes.include?(node)}

      raw_edges = []
      nodes.each do |node|
        @each_edge.call(node) {|edge| raw_edges << normalize_edge(node, edge)}
      end

      diagnostics = validate_terminals(nodes)
      known_edges, endpoint_diagnostics = classify_edges(nodes, raw_edges)
      diagnostics.concat(endpoint_diagnostics)
      duplicate_diagnostics = duplicate_identity_diagnostics(known_edges)
      diagnostics.concat(duplicate_diagnostics)

      cyclic_edges = cyclic_edge_indexes(nodes, known_edges)
      from_source, to_target = reachability(nodes, known_edges)
      structural_diagnostics = structural_diagnostics(
        nodes, known_edges, cyclic_edges, from_source, to_target)
      diagnostics.concat(structural_diagnostics)

      non_reducible_diagnostics =
        diagnostics.reject {|diagnostic| diagnostic.code == :cyclic_edge}
      if non_reducible_diagnostics.any?
        initial_edges = raw_edges.each_with_index.each_with_object([]) do |(edge, edge_index), list|
          if nodes.include?(edge.source) && nodes.include?(edge.target)
            list << Decomposition::Edge.new(
              edge.source, edge.target, edge.id, uid: "edge-#{edge_index}")
          end
        end
        residual_graph = Graph.new(nodes, initial_edges, nodes)
        tree = nil
        operations = []
      else
        residual_graph, tree, operations =
          reduce(nodes, known_edges, cyclic_edges)
        tree = nil if diagnostics.any?
      end

      unless tree
        if diagnostics.empty?
          diagnostics << Diagnostic.new(
            :reduction_stuck,
            "series/parallel reduction stopped before reaching one " \
            "#{@source.inspect}->#{@target.inspect} edge")
        end
      end

      certificate = Certificate.new(
        @source, @target, nodes, raw_edges, operations)
      SeriesParallelResult.new(
        @source, @target, tree, residual_graph, diagnostics, certificate)
    end

    private

    def normalize_edge(node, edge)
      if edge.respond_to?(:source) && edge.respond_to?(:target)
        id = edge.respond_to?(:id) ? edge.id : nil
        DirectedEdge.new(edge.source, edge.target, id)
      elsif edge.is_a?(Array) && (edge.size == 2 || edge.size == 3)
        DirectedEdge.new(edge[0], edge[1], edge[2])
      else
        DirectedEdge.new(node, edge, nil)
      end
    end

    def validate_terminals(nodes)
      diagnostics = []
      unless nodes.include?(@source)
        diagnostics << Diagnostic.new(
          :source_not_found,
          "source #{@source.inspect} is not a node",
          node: @source)
      end
      unless nodes.include?(@target)
        diagnostics << Diagnostic.new(
          :sink_not_found,
          "sink #{@target.inspect} is not a node",
          node: @target)
      end
      if @source == @target
        diagnostics << Diagnostic.new(
          :same_source_and_sink,
          "source and sink must be distinct",
          node: @source)
      end
      diagnostics
    end

    def classify_edges(nodes, raw_edges)
      known = []
      diagnostics = []
      raw_edges.each do |edge|
        unless nodes.include?(edge.source) && nodes.include?(edge.target)
          diagnostics << Diagnostic.new(
            :unknown_edge_endpoint,
            "edge #{edge.source.inspect}->#{edge.target.inspect} has an endpoint which is not a node",
            edge: edge)
          next
        end
        known << edge
      end
      [known, diagnostics]
    end

    def duplicate_identity_diagnostics(edges)
      counts = Hash.new(0)
      edges.each {|edge| counts[edge.id] += 1 unless edge.id.nil?}
      edges.select do |edge|
        !edge.id.nil? && counts[edge.id] > 1
      end.map do |edge|
        Diagnostic.new(
          :duplicate_edge_identity,
          "edge identity #{edge.id.inspect} is used more than once",
          edge: edge)
      end
    end

    def cyclic_edge_indexes(nodes, edges)
      adjacency = Hash.new {|hash, key| hash[key] = []}
      edges.each {|edge| adjacency[edge.source] << edge.target}
      each_node = lambda {|&block| nodes.each(&block)}
      each_child = lambda {|node, &block| adjacency[node].each(&block)}
      cyclic_nodes = {}

      TSort.each_strongly_connected_component(each_node, each_child) do |component|
        if component.size > 1 || adjacency[component.first].include?(component.first)
          component.each {|node| cyclic_nodes[node] = true}
        end
      end

      edges.each_with_index.each_with_object({}) do |(edge, edge_index), result|
        if cyclic_nodes[edge.source] && cyclic_nodes[edge.target]
          result[edge_index] = true
        end
      end
    end

    def reachability(nodes, edges)
      forward = Hash.new {|hash, key| hash[key] = []}
      backward = Hash.new {|hash, key| hash[key] = []}
      edges.each do |edge|
        forward[edge.source] << edge.target
        backward[edge.target] << edge.source
      end
      [reachable(@source, forward), reachable(@target, backward)]
    end

    def reachable(start, adjacency)
      result = {}
      stack = [start]
      until stack.empty?
        node = stack.pop
        next if result[node]
        result[node] = true
        adjacency[node].each {|child| stack << child}
      end
      result
    end

    def structural_diagnostics(nodes, edges, cyclic_edges, from_source, to_target)
      diagnostics = []

      nodes.each do |node|
        incident = edges.any? do |edge|
          edge.source == node || edge.target == node
        end
        unless incident
          diagnostics << Diagnostic.new(
            :isolated_node,
            "node #{node.inspect} is isolated and cannot belong to a two-terminal graph",
            node: node)
          next
        end

        unless from_source[node]
          diagnostics << Diagnostic.new(
            :node_not_reachable_from_source,
            "node #{node.inspect} is not reachable from source #{@source.inspect}",
            node: node)
        end
        unless to_target[node]
          diagnostics << Diagnostic.new(
            :node_cannot_reach_sink,
            "node #{node.inspect} cannot reach sink #{@target.inspect}",
            node: node)
        end
      end

      edges.each_with_index do |edge, edge_index|
        if cyclic_edges[edge_index]
          diagnostics << Diagnostic.new(
            :cyclic_edge,
            "edge #{edge.source.inspect}->#{edge.target.inspect} is part of a directed cycle or back edge",
            edge: edge)
        end

        unless from_source[edge.source] && to_target[edge.target]
          diagnostics << Diagnostic.new(
            :edge_not_on_source_sink_path,
            "edge #{edge.source.inspect}->#{edge.target.inspect} is not on a source-to-sink path",
            edge: edge)
        end
      end

      diagnostics
    end

    def reduce(nodes, edges, cyclic_indexes)
      unless terminals_available?(nodes)
        return [Graph.new([], [], nodes), nil, []]
      end

      index = {}
      nodes.each_with_index {|node, i| index[node] = i}
      incoming = nodes.map {[]}
      outgoing = nodes.map {[]}
      active_edges = {}
      pairs = {}
      operations = []
      cyclic = {}

      grouped = Hash.new {|hash, key| hash[key] = []}
      edges.each_with_index do |edge, edge_index|
        uid = "edge-#{edge_index}"
        tree = Decomposition::Edge.new(
          edge.source, edge.target, edge.id, uid: uid)
        grouped[[index[edge.source], index[edge.target]]] << tree
        cyclic[uid] = true if cyclic_indexes[edge_index]
      end

      grouped.each do |(source_index, target_index), group|
        tree = group.first
        group[1..-1].each do |next_tree|
          tree = merge_parallel(
            tree, next_tree, cyclic, operations)
        end
        add_active_edge(
          source_index, target_index, tree,
          incoming, outgoing, active_edges, pairs)
      end

      active_nodes = nodes.map {true}
      queue = []
      nodes.each_with_index do |_, node_index|
        unless node_index == index[@source] || node_index == index[@target]
          queue << node_index
        end
      end

      until queue.empty?
        node_index = queue.shift
        next unless active_nodes[node_index]
        next unless incoming[node_index].size == 1 &&
                    outgoing[node_index].size == 1

        incoming_uid = incoming[node_index].first
        outgoing_uid = outgoing[node_index].first
        next if cyclic[incoming_uid] || cyclic[outgoing_uid]

        incoming_tree = active_edges.delete(incoming_uid)
        outgoing_tree = active_edges.delete(outgoing_uid)
        source_index = index[incoming_tree.source]
        target_index = index[outgoing_tree.target]

        remove_edge(
          source_index, node_index, incoming_uid, incoming, outgoing)
        remove_edge(
          node_index, target_index, outgoing_uid, incoming, outgoing)
        active_nodes[node_index] = false

        series_uid = next_uid("series")
        operations << ReductionOperation.new(
          :series, incoming_tree.source, outgoing_tree.target,
          [incoming_uid, outgoing_uid], series_uid)
        tree = Decomposition::Series.build(
          incoming_tree.source, outgoing_tree.target,
          [incoming_tree, outgoing_tree], uid: series_uid)
        result_uid = series_uid

        existing_uid = pairs[[source_index, target_index]]
        if existing_uid
          existing_tree = active_edges.delete(existing_uid)
          remove_edge(
            source_index, target_index, existing_uid, incoming, outgoing)
          parallel_uid = next_uid("parallel")
          operations << ReductionOperation.new(
            :parallel, tree.source, tree.target,
            [existing_uid, result_uid], parallel_uid)
          tree = Decomposition::Parallel.build(
            tree.source, tree.target,
            [existing_tree, tree], uid: parallel_uid)
          result_uid = parallel_uid
          cyclic[result_uid] = cyclic[existing_uid]
        end

        add_active_edge(
          source_index, target_index, tree,
          incoming, outgoing, active_edges, pairs)
        enqueue_neighbor(source_index, queue, active_nodes, index)
        enqueue_neighbor(target_index, queue, active_nodes, index)
      end

      active_node_objects =
        nodes.select.with_index {|_, node_index| active_nodes[node_index]}
      residual_graph = Graph.new(
        active_node_objects, active_edges.values, nodes)
      tree =
        if active_node_objects == [@source, @target] &&
           active_edges.size == 1 &&
           pairs[[index[@source], index[@target]]]
          active_edges.values.first
        end
      [residual_graph, tree, operations]
    end

    def merge_parallel(first, second, cyclic, operations)
      uid = next_uid("parallel")
      operations << ReductionOperation.new(
        :parallel, first.source, first.target,
        [first.uid, second.uid], uid)
      cyclic[uid] = cyclic[first.uid] || cyclic[second.uid]
      Decomposition::Parallel.build(
        first.source, first.target, [first, second], uid: uid)
    end

    def add_active_edge(source_index, target_index, tree,
                        incoming, outgoing, active_edges, pairs)
      active_edges[tree.uid] = tree
      pairs[[source_index, target_index]] = tree.uid
      outgoing[source_index] << tree.uid
      incoming[target_index] << tree.uid
    end

    def remove_edge(source_index, target_index, uid, incoming, outgoing)
      outgoing[source_index].delete(uid)
      incoming[target_index].delete(uid)
    end

    def enqueue_neighbor(node_index, queue, active_nodes, index)
      return unless active_nodes[node_index]
      return if node_index == index[@source] ||
                node_index == index[@target]
      queue << node_index unless queue.include?(node_index)
    end

    def terminals_available?(nodes)
      @source != @target &&
        nodes.include?(@source) &&
        nodes.include?(@target)
    end

    def next_uid(prefix)
      @sequence += 1
      "#{prefix}-#{@sequence}"
    end
  end
  private_constant :SeriesParallelReducer

  # Exception class to be raised when a cycle is found.
  class Cyclic < StandardError
  end

  # Returns a topologically sorted array of nodes.
  # The array is sorted from children to parents, i.e.
  # the first element has no child and the last node has no parent.
  #
  # If there is a cycle, TSort::Cyclic is raised.
  #
  #   class G
  #     include TSort
  #     def initialize(g)
  #       @g = g
  #     end
  #     def tsort_each_child(n, &b) @g[n].each(&b) end
  #     def tsort_each_node(&b) @g.each_key(&b) end
  #   end
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]})
  #   p graph.tsort #=> [4, 2, 3, 1]
  #
  #   graph = G.new({1=>[2], 2=>[3, 4], 3=>[2], 4=>[]})
  #   p graph.tsort # raises TSort::Cyclic
  #
  def tsort
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.tsort(each_node, each_child)
  end

  # Returns a topologically sorted array of nodes.
  # The array is sorted from children to parents, i.e.
  # the first element has no child and the last node has no parent.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # _each_node_ should have +call+ method which yields for each node in the graph.
  # _each_child_ should have +call+ method which takes a node argument and yields for each child node.
  #
  # If there is a cycle, TSort::Cyclic is raised.
  #
  #   g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   p TSort.tsort(each_node, each_child) #=> [4, 2, 3, 1]
  #
  #   g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   p TSort.tsort(each_node, each_child) # raises TSort::Cyclic
  #
  def self.tsort(each_node, each_child)
    tsort_each(each_node, each_child).to_a
  end

  # The iterator version of the #tsort method.
  # <tt><em>obj</em>.tsort_each</tt> is similar to <tt><em>obj</em>.tsort.each</tt>, but
  # modification of _obj_ during the iteration may lead to unexpected results.
  #
  # #tsort_each returns +nil+.
  # If there is a cycle, TSort::Cyclic is raised.
  #
  #   class G
  #     include TSort
  #     def initialize(g)
  #       @g = g
  #     end
  #     def tsort_each_child(n, &b) @g[n].each(&b) end
  #     def tsort_each_node(&b) @g.each_key(&b) end
  #   end
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]})
  #   graph.tsort_each {|n| p n }
  #   #=> 4
  #   #   2
  #   #   3
  #   #   1
  #
  def tsort_each(&block) # :yields: node
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.tsort_each(each_node, each_child, &block)
  end

  # The iterator version of the TSort.tsort method.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # _each_node_ should have +call+ method which yields for each node in the graph.
  # _each_child_ should have +call+ method which takes a node argument and yields for each child node.
  #
  #   g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   TSort.tsort_each(each_node, each_child) {|n| p n }
  #   #=> 4
  #   #   2
  #   #   3
  #   #   1
  #
  def self.tsort_each(each_node, each_child) # :yields: node
    return to_enum(__method__, each_node, each_child) unless block_given?

    each_strongly_connected_component(each_node, each_child) {|component|
      if component.size == 1
        yield component.first
      else
        raise Cyclic.new("topological sort failed: #{component.inspect}")
      end
    }
  end

  # Returns strongly connected components as an array of arrays of nodes.
  # The array is sorted from children to parents.
  # Each elements of the array represents a strongly connected component.
  #
  #   class G
  #     include TSort
  #     def initialize(g)
  #       @g = g
  #     end
  #     def tsort_each_child(n, &b) @g[n].each(&b) end
  #     def tsort_each_node(&b) @g.each_key(&b) end
  #   end
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]})
  #   p graph.strongly_connected_components #=> [[4], [2], [3], [1]]
  #
  #   graph = G.new({1=>[2], 2=>[3, 4], 3=>[2], 4=>[]})
  #   p graph.strongly_connected_components #=> [[4], [2, 3], [1]]
  #
  def strongly_connected_components
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.strongly_connected_components(each_node, each_child)
  end

  # Returns strongly connected components as an array of arrays of nodes.
  # The array is sorted from children to parents.
  # Each elements of the array represents a strongly connected component.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # _each_node_ should have +call+ method which yields for each node in the graph.
  # _each_child_ should have +call+ method which takes a node argument and yields for each child node.
  #
  #   g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   p TSort.strongly_connected_components(each_node, each_child)
  #   #=> [[4], [2], [3], [1]]
  #
  #   g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   p TSort.strongly_connected_components(each_node, each_child)
  #   #=> [[4], [2, 3], [1]]
  #
  def self.strongly_connected_components(each_node, each_child)
    each_strongly_connected_component(each_node, each_child).to_a
  end

  # The iterator version of the #strongly_connected_components method.
  # <tt><em>obj</em>.each_strongly_connected_component</tt> is similar to
  # <tt><em>obj</em>.strongly_connected_components.each</tt>, but
  # modification of _obj_ during the iteration may lead to unexpected results.
  #
  # #each_strongly_connected_component returns +nil+.
  #
  #   class G
  #     include TSort
  #     def initialize(g)
  #       @g = g
  #     end
  #     def tsort_each_child(n, &b) @g[n].each(&b) end
  #     def tsort_each_node(&b) @g.each_key(&b) end
  #   end
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]})
  #   graph.each_strongly_connected_component {|scc| p scc }
  #   #=> [4]
  #   #   [2]
  #   #   [3]
  #   #   [1]
  #
  #   graph = G.new({1=>[2], 2=>[3, 4], 3=>[2], 4=>[]})
  #   graph.each_strongly_connected_component {|scc| p scc }
  #   #=> [4]
  #   #   [2, 3]
  #   #   [1]
  #
  def each_strongly_connected_component(&block) # :yields: nodes
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.each_strongly_connected_component(each_node, each_child, &block)
  end

  # The iterator version of the TSort.strongly_connected_components method.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # _each_node_ should have +call+ method which yields for each node in the graph.
  # _each_child_ should have +call+ method which takes a node argument and yields for each child node.
  #
  #   g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   TSort.each_strongly_connected_component(each_node, each_child) {|scc| p scc }
  #   #=> [4]
  #   #   [2]
  #   #   [3]
  #   #   [1]
  #
  #   g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   TSort.each_strongly_connected_component(each_node, each_child) {|scc| p scc }
  #   #=> [4]
  #   #   [2, 3]
  #   #   [1]
  #
  def self.each_strongly_connected_component(each_node, each_child) # :yields: nodes
    return to_enum(__method__, each_node, each_child) unless block_given?

    id_map = {}
    stack = []
    each_node.call {|node|
      unless id_map.include? node
        each_strongly_connected_component_from(node, each_child, id_map, stack) {|c|
          yield c
        }
      end
    }
    nil
  end

  # Iterates over strongly connected component in the subgraph reachable from
  # _node_.
  #
  # Return value is unspecified.
  #
  # #each_strongly_connected_component_from doesn't call #tsort_each_node.
  #
  #   class G
  #     include TSort
  #     def initialize(g)
  #       @g = g
  #     end
  #     def tsort_each_child(n, &b) @g[n].each(&b) end
  #     def tsort_each_node(&b) @g.each_key(&b) end
  #   end
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]})
  #   graph.each_strongly_connected_component_from(2) {|scc| p scc }
  #   #=> [4]
  #   #   [2]
  #
  #   graph = G.new({1=>[2], 2=>[3, 4], 3=>[2], 4=>[]})
  #   graph.each_strongly_connected_component_from(2) {|scc| p scc }
  #   #=> [4]
  #   #   [2, 3]
  #
  def each_strongly_connected_component_from(node, id_map={}, stack=[], &block) # :yields: nodes
    TSort.each_strongly_connected_component_from(node, method(:tsort_each_child), id_map, stack, &block)
  end

  # Iterates over strongly connected components in a graph.
  # The graph is represented by _node_ and _each_child_.
  #
  # _node_ is the first node.
  # _each_child_ should have +call+ method which takes a node argument
  # and yields for each child node.
  #
  # Return value is unspecified.
  #
  # #TSort.each_strongly_connected_component_from is a class method and
  # it doesn't need a class to represent a graph which includes TSort.
  #
  #   graph = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
  #   each_child = lambda {|n, &b| graph[n].each(&b) }
  #   TSort.each_strongly_connected_component_from(1, each_child) {|scc|
  #     p scc
  #   }
  #   #=> [4]
  #   #   [2, 3]
  #   #   [1]
  #
  def self.each_strongly_connected_component_from(node, each_child, id_map={}, stack=[]) # :yields: nodes
    return to_enum(__method__, node, each_child, id_map, stack) unless block_given?

    minimum_id = node_id = id_map[node] = id_map.size
    stack_length = stack.length
    stack << node

    each_child.call(node) {|child|
      if id_map.include? child
        child_id = id_map[child]
        minimum_id = child_id if child_id && child_id < minimum_id
      else
        sub_minimum_id =
          each_strongly_connected_component_from(child, each_child, id_map, stack) {|c|
            yield c
          }
        minimum_id = sub_minimum_id if sub_minimum_id < minimum_id
      end
    }

    if node_id == minimum_id
      component = stack.slice!(stack_length .. -1)
      component.each {|n| id_map[n] = nil}
      yield component
    end

    minimum_id
  end

  # Should be implemented by a extended class.
  #
  # #tsort_each_node is used to iterate for all nodes over a graph.
  #
  def tsort_each_node # :yields: node
    raise NotImplementedError.new
  end

  # Should be implemented by a extended class.
  #
  # #tsort_each_child is used to iterate for child nodes of _node_.
  #
  def tsort_each_child(node) # :yields: child
    raise NotImplementedError.new
  end

  # Yields each edge leaving _node_. Edge objects should respond to
  # #source and #target, and may respond to #id to expose their identity.
  #
  # The default implementation derives edge objects from
  # #tsort_each_child. Parallel occurrences receive distinct synthetic
  # identities so they are not merged before recognition.
  def tsort_each_edge(node) # :yields: edge
    return enum_for(:tsort_each_edge, node) unless block_given?

    occurrence = 0
    tsort_each_child(node) do |child|
      yield DirectedEdge.new(node, child, [node, occurrence])
      occurrence += 1
    end
  end

  # Recognizes a directed two-terminal series-parallel graph with the given
  # source and sink. On success, #tree on the result is an expandable
  # decomposition. On failure, #residual_graph is the graph remaining when
  # series/parallel reduction stops, and #diagnostics explains isolated
  # nodes, cycles or back edges, components outside source-sink paths,
  # duplicate edge identities, and terminal problems.
  def series_parallel_decomposition(source, target)
    TSort.series_parallel_decomposition(
      source, target,
      method(:tsort_each_node), method(:tsort_each_edge))
  end

  # The module-function version of #series_parallel_decomposition.
  # _each_node_ yields all nodes. _each_edge_ receives a node and yields the
  # edge objects leaving that node.
  def self.series_parallel_decomposition(source, target, each_node, each_edge)
    SeriesParallelReducer.run(source, target, each_node, each_edge)
  end
end
