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

  # Exception class to be raised when a cycle is found.
  class Cyclic < StandardError
  end

  # Exception class to be raised when the number of subset states visited
  # while counting linear extensions exceeds the configured budget.
  class StateBudgetExceeded < StandardError
  end

  # Default upper bound on the number of subset states visited by the
  # linear extension counting DP.  The DP needs up to 2**n states for a
  # graph of n nodes, so the default keeps these methods usable only for
  # small graphs; pass an explicit +max_states:+ to raise the limit.
  DEFAULT_MAX_STATES = 100_000

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
  # Returns the exact number of linear extensions of the graph as an
  # Integer.
  #
  # A linear extension is an ordering of the nodes in which every node
  # appears after all of its children, i.e. a valid execution order for
  # dependency-first scheduling.  #tsort returns one such ordering;
  # #linear_extension_count tells how many exist in total.
  #
  # The count is computed exactly with a dynamic program over node
  # subsets.  Ruby Integers have arbitrary precision, so counts larger
  # than 64 bits are returned exactly.  The number of subset states is
  # bounded by +max_states+ (TSort::DEFAULT_MAX_STATES by default); when
  # the budget is exceeded, TSort::StateBudgetExceeded is raised instead
  # of silently running forever.  This makes the method suitable for
  # small graphs only.
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
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[4], 4=>[]})
  #   p graph.linear_extension_count #=> 2
  #
  def linear_extension_count(max_states: DEFAULT_MAX_STATES)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_count(each_node, each_child, max_states: max_states)
  end

  # Returns the number of linear extensions of the graph.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # _each_node_ should have +call+ method which yields for each node in the graph.
  # _each_child_ should have +call+ method which takes a node argument and yields for each child node.
  #
  # See #linear_extension_count for the semantics and the state budget.
  #
  #   g = {1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}
  #   each_node = lambda {|&b| g.each_key(&b) }
  #   each_child = lambda {|n, &b| g[n].each(&b) }
  #   p TSort.linear_extension_count(each_node, each_child) #=> 2
  #
  def self.linear_extension_count(each_node, each_child, max_states: DEFAULT_MAX_STATES)
    LinearExtensionCounter.new(each_node, each_child, max_states).count
  end

  # Returns the _rank_-th linear extension of the graph as an array of
  # nodes, ordered from children to parents.
  #
  # Linear extensions are numbered 0 ... count-1 in lexicographic order
  # of the canonical node order (the order in which #tsort_each_node
  # first yields the nodes).  Together with #linear_extension_count and
  # #linear_extension_rank this gives an exact ranking/unranking bijection
  # between integers and execution orders.
  #
  # Raises ArgumentError if _rank_ is out of range, TSort::Cyclic if the
  # graph has a cycle, and TSort::StateBudgetExceeded if the counting DP
  # exceeds +max_states+ subset states.
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[4], 4=>[]})
  #   p graph.linear_extension_unrank(0) #=> [4, 2, 3, 1]
  #   p graph.linear_extension_unrank(1) #=> [4, 3, 2, 1]
  #
  def linear_extension_unrank(rank, max_states: DEFAULT_MAX_STATES)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_unrank(each_node, each_child, rank, max_states: max_states)
  end

  # Returns the _rank_-th linear extension of the graph.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # See #linear_extension_unrank for the ranking convention.
  #
  def self.linear_extension_unrank(each_node, each_child, rank, max_states: DEFAULT_MAX_STATES)
    LinearExtensionCounter.new(each_node, each_child, max_states).unrank(rank)
  end

  # Returns the rank of _order_, an array of nodes, among all linear
  # extensions of the graph.  The result is an Integer in
  # 0 ... linear_extension_count such that
  #
  #   graph.linear_extension_unrank(graph.linear_extension_rank(order)) == order
  #
  # holds for every linear extension _order_.
  #
  # Raises ArgumentError if _order_ is not a linear extension of the
  # graph, TSort::Cyclic if the graph has a cycle, and
  # TSort::StateBudgetExceeded if the counting DP exceeds +max_states+
  # subset states.
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[4], 4=>[]})
  #   p graph.linear_extension_rank([4, 2, 3, 1]) #=> 0
  #   p graph.linear_extension_rank([4, 3, 2, 1]) #=> 1
  #
  def linear_extension_rank(order, max_states: DEFAULT_MAX_STATES)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_rank(each_node, each_child, order, max_states: max_states)
  end

  # Returns the rank of _order_ among all linear extensions of the graph.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # See #linear_extension_rank for the ranking convention.
  #
  def self.linear_extension_rank(each_node, each_child, order, max_states: DEFAULT_MAX_STATES)
    LinearExtensionCounter.new(each_node, each_child, max_states).rank(order)
  end

  # Returns a uniformly random linear extension of the graph as an array
  # of nodes, ordered from children to parents.
  #
  # Unlike repeatedly picking a random node with no remaining children
  # (which is biased, because different prefixes leave different numbers
  # of completions), this samples exactly uniformly: a rank is drawn
  # uniformly from 0 ... linear_extension_count using _random_ (any
  # object responding to #rand like Random does) and mapped back through
  # the exact counting DP.
  #
  # Raises TSort::Cyclic if the graph has a cycle and
  # TSort::StateBudgetExceeded if the counting DP exceeds +max_states+
  # subset states.
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[4], 4=>[]})
  #   p graph.linear_extension_sample(random: Random.new(42))
  #   #=> [4, 2, 3, 1] or [4, 3, 2, 1], each with probability 1/2
  #
  def linear_extension_sample(random: Random, max_states: DEFAULT_MAX_STATES)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_sample(each_node, each_child, random: random, max_states: max_states)
  end

  # Returns a uniformly random linear extension of the graph.
  #
  # The graph is represented by _each_node_ and _each_child_.
  # See #linear_extension_sample for the sampling semantics.
  #
  def self.linear_extension_sample(each_node, each_child, random: Random, max_states: DEFAULT_MAX_STATES)
    LinearExtensionCounter.new(each_node, each_child, max_states).sample(random)
  end

  # Exact counting, ranking, unranking and uniform sampling of linear
  # extensions via a memoized dynamic program over node subsets.
  #
  # The state of the DP is the set of nodes already placed (in
  # children-to-parents execution order); f(state) is the number of
  # completions of that prefix.  All arithmetic uses Ruby Integers, which
  # have arbitrary precision, so counts and ranks are exact for any size.
  class LinearExtensionCounter # :nodoc:
    def initialize(each_node, each_child, max_states)
      @max_states = max_states
      @nodes = []
      @index = {}
      each_node.call {|node|
        unless @index.include?(node)
          @index[node] = @nodes.size
          @nodes << node
        end
      }
      child_lists = []
      scanned = 0
      while scanned < @nodes.size
        node = @nodes[scanned]
        scanned += 1
        list = []
        each_child.call(node) {|child|
          unless @index.include?(child)
            @index[child] = @nodes.size
            @nodes << child
          end
          list << child
        }
        child_lists << list
      end
      n = @nodes.size
      @full = (1 << n) - 1
      @children = Array.new(n, 0)
      child_lists.each_with_index do |list, i|
        mask = 0
        list.each {|child| mask |= 1 << @index[child] }
        @children[i] = mask
      end
      @memo = {}
      @states = 0
    end

    # Exact number of linear extensions.  Raises TSort::Cyclic if the
    # graph has a cycle (then no linear extension exists).
    def count
      result = completions(0)
      if result == 0
        raise Cyclic.new("linear extension counting failed: the graph has a cycle")
      end
      result
    end

    # The _rank_-th linear extension, 0-based, in lexicographic order of
    # the canonical node order.
    def unrank(rank)
      total = count
      unless Integer === rank && 0 <= rank && rank < total
        raise ArgumentError.new("rank #{rank.inspect} out of range 0...#{total}")
      end
      state = 0
      order = []
      until state == @full
        each_placeable(state) do |i|
          c = completions(state | (1 << i))
          if rank < c
            order << @nodes[i]
            state |= 1 << i
            break
          end
          rank -= c
        end
      end
      order
    end

    # The rank of _order_ among all linear extensions.
    def rank(order)
      count
      unless order.size == @nodes.size
        raise ArgumentError.new("not a linear extension of this graph: #{order.inspect}")
      end
      result = 0
      state = 0
      order.each do |node|
        i = @index[node]
        unless i
          raise ArgumentError.new("unknown node: #{node.inspect}")
        end
        bit = 1 << i
        if (state & bit) != 0
          raise ArgumentError.new("duplicate node: #{node.inspect}")
        end
        if (@children[i] & ~state) != 0
          raise ArgumentError.new("node #{node.inspect} appears before its child")
        end
        each_placeable(state) do |j|
          break if j == i
          result += completions(state | (1 << j))
        end
        state |= bit
      end
      result
    end

    # A uniformly random linear extension, sampled by drawing a uniform
    # rank and unranking it.
    def sample(random)
      unrank(random.rand(count))
    end

    private

    # Number of completions of the partial order _state_ (a bitmask of
    # already placed nodes), memoized.  The number of memoized states is
    # bounded by the configured budget.
    def completions(state)
      return 1 if state == @full
      cached = @memo[state]
      return cached if cached
      if @states >= @max_states
        raise StateBudgetExceeded.new(
          "linear extension state budget exceeded (#{@max_states} states); " +          "the graph is too large, pass a bigger max_states: to proceed")
      end
      @states += 1
      total = 0
      each_placeable(state) do |i|
        total += completions(state | (1 << i))
      end
      @memo[state] = total
    end

    # Yields the indices of nodes that may be placed next: not yet
    # placed and with all children already placed.
    def each_placeable(state)
      i = 0
      n = @nodes.size
      while i < n
        if (state & (1 << i)) == 0 && (@children[i] & ~state) == 0
          yield i
        end
        i += 1
      end
    end
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
end
