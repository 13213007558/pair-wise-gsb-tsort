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

  # Edge identity used when a graph only implements #tsort_each_child.
  # Repeated occurrences of the same child are treated as parallel edges.
  SyntheticEdge = Struct.new(:tail, :head, :occurrence)

  # A node in a two-terminal series-parallel decomposition tree.
  Decomposition = Struct.new(:type, :source, :sink, :edge, :children) do
    def leaf?
      type == :edge
    end

    def each_original_edge # :yields: edge, source, sink
      return enum_for(__method__) unless block_given?

      if leaf?
        yield edge, source, sink
      else
        children.each do |child|
          child.each_original_edge do |original_edge, edge_source, edge_sink|
            yield original_edge, edge_source, edge_sink
          end
        end
      end
    end

    def expand
      graph = SeriesParallel::Graph.new(source, sink)
      each_original_edge do |edge, edge_source, edge_sink|
        graph.add_edge(edge, edge_source, edge_sink)
      end
      graph
    end
  end

  module SeriesParallel
    ReducedEdge = Struct.new(:index)

    def self.recognize(each_node, each_child, source, sink, each_edge)
      nodes = []
      node_map = {}
      add_node = lambda do |node|
        next if node_map[node]
        node_map[node] = true
        nodes << node
      end

      each_node.call(&add_node)
      unless source != sink && node_map[source] && node_map[sink]
        raise ArgumentError, "distinct source and sink must be graph nodes"
      end

      adjacency = Hash.new {|hash, node| hash[node] = []}
      edges = {}

      if each_edge
        nodes.each do |node|
          each_edge.call(node) do |edge, child|
            if edges[edge]
              raise ArgumentError, "duplicate edge identity: #{edge.inspect}"
            end
            add_node.call(child)
            edges[edge] = [node, child]
            adjacency[node] << [edge, child]
          end
        end
      else
        occurrences = Hash.new(0)
        nodes.each do |node|
          each_child.call(node) do |child|
            add_node.call(child)
            key = [node, child]
            edge = SyntheticEdge.new(node, child, occurrences[key])
            occurrences[key] += 1
            edges[edge] = [node, child]
            adjacency[node] << [edge, child]
          end
        end
      end

      nodes.each {|node| adjacency[node] }

      components = strongly_connected_components(nodes, adjacency)
      component_id = {}
      component_nodes = {}
      components.each do |component|
        id = component_id.size
        component_nodes[id] = component
        component.each {|node| component_id[node] = id }
      end

      forward = reachable(source, adjacency)
      reverse_adjacency = reverse_edges(edges)
      backward = reachable(sink, reverse_adjacency)
      path_nodes = forward & backward

      incident_nodes = edges.values.flatten.uniq
      isolated_nodes = nodes.reject {|node| incident_nodes.include?(node) }
      cyclic_nodes = nodes.select do |node|
        component_nodes[component_id[node]].size > 1 ||
          adjacency[node].any? {|_edge, child| child == node }
      end
      cyclic_edges = edges.select do |_edge, (tail, head)|
        tail == head || component_id[tail] == component_id[head]
      end.keys
      edges_entering_source =
        edges.select {|_edge, (_tail, head)| head == source }.keys
      edges_leaving_sink =
        edges.select {|_edge, (tail, _head)| tail == sink }.keys
      off_path_nodes = nodes.reject {|node| path_nodes.include?(node) }
      off_path_edges = edges.select do |_edge, (tail, head)|
        !(path_nodes.include?(tail) && path_nodes.include?(head))
      end.keys

      diagnostics = {
        isolated_nodes: isolated_nodes,
        unreachable_nodes: nodes.reject {|node| forward.include?(node) },
        nodes_unable_to_reach_sink:
          nodes.reject {|node| backward.include?(node) },
        nodes_not_on_source_sink_path: off_path_nodes,
        cyclic_nodes: cyclic_nodes,
        cyclic_edges: cyclic_edges,
        edges_entering_source: edges_entering_source,
        edges_leaving_sink: edges_leaving_sink,
        edges_not_on_source_sink_path: off_path_edges
      }

      Recognizer.new(
        nodes, edges, source, sink, diagnostics, path_nodes
      ).recognize
    end

    def self.strongly_connected_components(nodes, adjacency)
      each_node = lambda {|&block| nodes.each(&block) }
      each_child = lambda do |node, &block|
        adjacency[node].each {|_edge, child| block.call(child) }
      end
      TSort.strongly_connected_components(each_node, each_child)
    end
    private_class_method :strongly_connected_components

    def self.reachable(start, adjacency)
      seen = {start => true}
      pending = [start]
      until pending.empty?
        node = pending.shift
        adjacency[node].each do |_edge, child|
          next if seen[child]
          seen[child] = true
          pending << child
        end
      end
      seen.keys
    end
    private_class_method :reachable

    def self.reverse_edges(edges)
      reverse = Hash.new {|hash, node| hash[node] = []}
      edges.each do |edge, (tail, head)|
        reverse[head] << [edge, tail]
      end
      reverse
    end
    private_class_method :reverse_edges

    class ReducedGraph
      include TSort

      attr_reader :edges, :parallel_groups

      def initialize(nodes, edge_data)
        @active_node_map = {}
        nodes.each do |node|
          next if @active_node_map[node]
          @active_node_map[node] = true
        end

        @outgoing = Hash.new {|hash, node| hash[node] = {}}
        @incoming = Hash.new {|hash, node| hash[node] = {}}
        @parallel_groups = Hash.new {|hash, endpoints| hash[endpoints] = {}}
        @edges = {}

        edge_data.each do |edge, data|
          if data.is_a?(Decomposition)
            add_edge(edge, data.source, data.sink, data)
          else
            add_edge(edge, data[0], data[1])
          end
        end
      end

      def self.snapshot(graph)
        new(graph.active_nodes, graph.edges.dup)
      end

      def add_node(node)
        return if @active_node_map[node]
        @active_node_map[node] = true
      end

      def add_edge(edge, source, sink, component=nil)
        raise ArgumentError, "duplicate edge: #{edge.inspect}" if @edges[edge]
        component ||= Decomposition.new(:edge, source, sink, edge, nil)
        unless component.source == source && component.sink == sink
          raise ArgumentError, "edge component endpoints do not match"
        end

        add_node(source)
        add_node(sink)
        @edges[edge] = component
        @outgoing[source][edge] = true
        @incoming[sink][edge] = true
        @parallel_groups[[source, sink]][edge] = true
      end

      def remove_edge(edge)
        component = @edges.delete(edge)
        raise ArgumentError, "unknown edge: #{edge.inspect}" unless component

        @outgoing[component.source].delete(edge)
        @incoming[component.sink].delete(edge)
        @parallel_groups[[component.source, component.sink]].delete(edge)
        component
      end

      def remove_node(node)
        unless @outgoing[node].empty? && @incoming[node].empty?
          raise ArgumentError, "node still has incident edges: #{node.inspect}"
        end
        @active_node_map.delete(node)
      end

      def active_nodes
        @active_node_map.keys
      end

      def outgoing_edges(node)
        @outgoing[node].keys
      end

      def incoming_edges(node)
        @incoming[node].keys
      end

      def edge_endpoints
        @edges.each_with_object({}) do |(edge, component), endpoints|
          endpoints[edge] = [component.source, component.sink]
        end
      end

      def tsort_each_node # :yields: node
        return to_enum(__method__) unless block_given?
        @active_node_map.each_key {|node| yield node }
      end

      def tsort_each_edge(node) # :yields: edge, child
        return to_enum(__method__, node) unless block_given?
        @outgoing[node].each_key do |edge|
          yield edge, @edges[edge].sink
        end
      end

      def tsort_each_child(node) # :yields: child
        return to_enum(__method__, node) unless block_given?
        @outgoing[node].each_key do |edge|
          yield @edges[edge].sink
        end
      end

      def apply_step(step)
        case step[0]
        when :parallel
          _, new_edge, old_edges, source, sink = step
          children = old_edges.map {|edge| @edges.fetch(edge) }
          unless old_edges.size >= 2 && old_edges.uniq == old_edges &&
                 children.all? {|child|
                   child.source == source && child.sink == sink
                 }
            raise ArgumentError, "invalid parallel reduction step"
          end
          old_edges.each {|edge| remove_edge(edge) }
          component = Decomposition.new(:parallel, source, sink, new_edge,
                                       children)
          add_edge(new_edge, source, sink, component)
        when :series
          _, new_edge, incoming_edge, outgoing_edge, source, middle, sink = step
          if incoming_edge == outgoing_edge
            raise ArgumentError, "invalid series reduction step"
          end
          incoming_component = @edges.fetch(incoming_edge)
          outgoing_component = @edges.fetch(outgoing_edge)
          unless incoming_component.source == source &&
                 incoming_component.sink == middle &&
                 outgoing_component.source == middle &&
                 outgoing_component.sink == sink
            raise ArgumentError, "invalid series reduction step"
          end
          remove_edge(incoming_edge)
          remove_edge(outgoing_edge)
          remove_node(middle)
          component = Decomposition.new(:series, source, sink, new_edge,
                                       [incoming_component, outgoing_component])
          add_edge(new_edge, source, sink, component)
        else
          raise ArgumentError, "unknown reduction step: #{step[0].inspect}"
        end
      end

      def ==(other)
        other.is_a?(ReducedGraph) &&
          active_nodes == other.active_nodes &&
          edges == other.edges
      end
    end

    class Graph
      include TSort

      attr_reader :source, :sink

      def initialize(source=nil, sink=nil)
        @nodes = []
        @node_map = {}
        @adjacency = Hash.new {|hash, node| hash[node] = []}
        @source = source
        @sink = sink
        add_node(source) if source
        add_node(sink) if sink
      end

      def add_node(node)
        return if @node_map[node]
        @node_map[node] = true
        @nodes << node
      end

      def add_edge(edge, source, sink)
        add_node(source)
        add_node(sink)
        @adjacency[source] << [edge, sink]
      end

      def tsort_each_node # :yields: node
        return to_enum(__method__) unless block_given?
        @nodes.each {|node| yield node }
      end

      def tsort_each_edge(node) # :yields: edge, child
        return to_enum(__method__, node) unless block_given?
        @adjacency[node].each {|edge, child| yield edge, child }
      end

      def tsort_each_child(node) # :yields: child
        return to_enum(__method__, node) unless block_given?
        @adjacency[node].each {|_edge, child| yield child }
      end
    end

    Result = Struct.new(:source, :sink, :ok, :decomposition, :residual,
                        :steps, :diagnostics, :initial_nodes, :initial_edges) do
      def ok?
        ok
      end

      def replay
        graph = ReducedGraph.new(initial_nodes, initial_edges)
        steps.each {|step| graph.apply_step(step) }
        graph
      end
    end

    class Recognizer < ReducedGraph
      attr_reader :initial_nodes, :initial_edges

      def initialize(nodes, edge_data, source, sink, diagnostics, path_nodes)
        super(nodes, edge_data)
        @initial_nodes = active_nodes.dup
        @initial_edges = {}
        edges.each do |edge, component|
          @initial_edges[edge] = [component.source, component.sink]
        end
        @source = source
        @sink = sink
        @diagnostics = diagnostics
        @path_node_map = {}
        path_nodes.each {|node| @path_node_map[node] = true }
        @steps = []
        @pending_parallel = []
        @pending_series = []
        @queued_series = {}

        @parallel_groups.each do |(group_source, group_sink), edges|
          next if group_source == group_sink
          next unless @path_node_map[group_source] && @path_node_map[group_sink]
          @pending_parallel << [group_source, group_sink] if edges.size > 1
        end
        active_nodes.each {|node| enqueue_series(node) }
      end

      def recognize
        loop do
          step = parallel_step || series_step
          break unless step

          apply_step(step)
          @steps << step

          new_edge = step[1]
          endpoints = [@edges[new_edge].source, @edges[new_edge].sink]
          @pending_parallel << endpoints if parallel_groups[endpoints].size > 1
          enqueue_series(endpoints[0])
          enqueue_series(endpoints[1])
        end

        component = edges.values.first
        component_edge = edges.keys.first
        success = fully_reduced? &&
                  edges.size == 1 &&
                  component.source == @source &&
                  component.sink == @sink &&
                  outgoing_edges(@source) == [component_edge] &&
                  incoming_edges(@sink) == [component_edge]

        Result.new(
          @source, @sink, success, success ? component : nil,
          ReducedGraph.snapshot(self), @steps, @diagnostics,
          @initial_nodes, @initial_edges
        )
      end

      private

      def fully_reduced?
        active_nodes.size == 2 &&
          @active_node_map[@source] &&
          @active_node_map[@sink]
      end

      def enqueue_series(node)
        return unless @active_node_map[node]
        return unless @path_node_map[node]
        return if node == @source || node == @sink
        return if @queued_series[node]
        return unless incoming_edges(node).size == 1
        return unless outgoing_edges(node).size == 1

        incoming_edge = incoming_edges(node).first
        outgoing_edge = outgoing_edges(node).first
        source = @edges[incoming_edge].source
        sink = @edges[outgoing_edge].sink
        return if source == sink
        @queued_series[node] = true
        @pending_series << node
      end

      def parallel_step
        endpoints = @pending_parallel.shift
        endpoints = @pending_parallel.shift while endpoints &&
          (endpoints[0] == endpoints[1] || parallel_groups[endpoints].size < 2)
        return unless endpoints

        old_edges = parallel_groups[endpoints].keys.dup
        new_edge = ReducedEdge.new(@steps.size)
        [:parallel, new_edge, old_edges, endpoints[0], endpoints[1]]
      end

      def series_step
        node = @pending_series.shift
        while node && !series_candidate?(node)
          @queued_series.delete(node)
          node = @pending_series.shift
        end
        return unless node
        @queued_series.delete(node)

        incoming_edge = incoming_edges(node).first
        outgoing_edge = outgoing_edges(node).first
        source = @edges[incoming_edge].source
        sink = @edges[outgoing_edge].sink
        new_edge = ReducedEdge.new(@steps.size)
        [:series, new_edge, incoming_edge, outgoing_edge, source, node, sink]
      end

      def series_candidate?(node)
        return false unless @active_node_map[node]
        return false unless @path_node_map[node]
        return false if node == @source || node == @sink
        return false unless incoming_edges(node).size == 1
        return false unless outgoing_edges(node).size == 1

        incoming_edge = incoming_edges(node).first
        outgoing_edge = outgoing_edges(node).first
        @edges[incoming_edge].source != @edges[outgoing_edge].sink
      end
    end
  end

  # The version string.
  VERSION = "0.2.0"

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

  # Recognizes a directed two-terminal series-parallel graph.
  #
  # _source_ and _sink_ are the required outer terminals.  On success,
  # TSort::SeriesParallel::Result#decomposition contains an expandable
  # series/parallel tree whose leaves are the original edge identities.
  # On failure, +residual+ is the graph after repeatedly applying all available
  # valid reductions, and +steps+ is a replayable certificate that constructs
  # that residual graph from the input.
  #
  # Parallel child occurrences are preserved.  A graph may also implement
  # #tsort_each_edge(node) and yield +(edge, child)+ pairs to provide explicit
  # edge identities.
  #
  # Isolated nodes, cycles/back edges, edges entering _source_, edges leaving
  # _sink_, and nodes or edges outside every source-to-sink path are listed in
  # +diagnostics+.  They remain represented in the residual graph and prevent
  # the terminal graph from reducing to one edge between _source_ and _sink_.
  def two_terminal_series_parallel(source, sink)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    each_edge = method(:tsort_each_edge) if respond_to?(:tsort_each_edge)
    TSort.two_terminal_series_parallel(
      each_node, each_child, source, sink, each_edge
    )
  end

  # The callable-graph version of #two_terminal_series_parallel.
  #
  # _each_edge_ is optional.  When supplied it receives a node and must yield
  # +(edge, child)+ pairs.  When omitted, repeated child occurrences become
  # distinct TSort::SyntheticEdge values.
  def self.two_terminal_series_parallel(each_node, each_child, source, sink,
                                       each_edge=nil)
    SeriesParallel.recognize(each_node, each_child, source, sink, each_edge)
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

  # Iterates edge identities and child nodes of _node_.
  # The default implementation creates a TSort::SyntheticEdge for each child
  # occurrence, so repeated children remain distinct parallel edges.
  def tsort_each_edge(node) # :yields: edge, child
    return to_enum(__method__, node) unless block_given?
    occurrence = 0
    tsort_each_child(node) do |child|
      yield SyntheticEdge.new(node, child, occurrence), child
      occurrence += 1
    end
  end
end
