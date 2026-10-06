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

  # Exception class to be raised when counting, ranking, unranking or
  # sampling linear extensions explores more subset states than the
  # configured state budget allows.
  class StateBudgetExceeded < StandardError
  end

  # Default limit on the number of subset states explored by the linear
  # extension methods.  A graph of n nodes has at most 2**n states, so
  # the default budget keeps these methods usable for small graphs only.
  DEFAULT_STATE_BUDGET = 100_000

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

  # Returns the exact number of linear extensions of the graph, i.e. the
  # number of valid execution orders in which every node appears after all
  # of its children.  The result is a Ruby Integer (bignum when large).
  #
  # The count is computed by dynamic programming over subsets of nodes, so
  # it is only feasible for small graphs.  At most _state_budget_ subset
  # states are explored; TSort::StateBudgetExceeded is raised when the
  # budget is exceeded.  TSort::Cyclic is raised if the graph has a cycle.
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
  def linear_extension_count(state_budget: DEFAULT_STATE_BUDGET)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_count(each_node, each_child, state_budget: state_budget)
  end

  # The class-method version of #linear_extension_count.
  # The graph is represented by _each_node_ and _each_child_.
  def self.linear_extension_count(each_node, each_child, state_budget: DEFAULT_STATE_BUDGET)
    counter = LinearExtensionCounter.new(each_node, each_child, state_budget)
    total = counter.total
    raise Cyclic.new("topological sort failed: the graph has a cycle") if total.zero?
    total
  end

  # Returns the rank of _order_, a valid execution order (linear
  # extension) given as an array of nodes from children to parents.
  # The rank is an Integer in <tt>0...linear_extension_count</tt>, and the
  # mapping between ranks and orders is a bijection: orders are numbered
  # lexicographically by the position of each node in #tsort_each_node
  # order.
  #
  # ArgumentError is raised if _order_ is not a valid linear extension of
  # the graph.  TSort::StateBudgetExceeded is raised when the state budget
  # is exceeded.
  #
  #   graph = G.new({1=>[], 2=>[], 3=>[]})
  #   p graph.linear_extension_rank([2, 3, 1]) #=> 3
  #
  def linear_extension_rank(order, state_budget: DEFAULT_STATE_BUDGET)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_rank(order, each_node, each_child, state_budget: state_budget)
  end

  # The class-method version of #linear_extension_rank.
  # The graph is represented by _each_node_ and _each_child_.
  def self.linear_extension_rank(order, each_node, each_child, state_budget: DEFAULT_STATE_BUDGET)
    counter = LinearExtensionCounter.new(each_node, each_child, state_budget)
    raise Cyclic.new("topological sort failed: the graph has a cycle") if counter.total.zero?
    counter.rank(order)
  end

  # Returns the linear extension whose rank is _rank_; the inverse of
  # #linear_extension_rank.
  #
  # ArgumentError is raised unless _rank_ is an Integer in
  # <tt>0...linear_extension_count</tt>.  TSort::Cyclic is raised if the
  # graph has a cycle.  TSort::StateBudgetExceeded is raised when the
  # state budget is exceeded.
  #
  #   graph = G.new({1=>[], 2=>[], 3=>[]})
  #   p graph.linear_extension_unrank(3) #=> [2, 3, 1]
  #
  def linear_extension_unrank(rank, state_budget: DEFAULT_STATE_BUDGET)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_unrank(rank, each_node, each_child, state_budget: state_budget)
  end

  # The class-method version of #linear_extension_unrank.
  # The graph is represented by _each_node_ and _each_child_.
  def self.linear_extension_unrank(rank, each_node, each_child, state_budget: DEFAULT_STATE_BUDGET)
    counter = LinearExtensionCounter.new(each_node, each_child, state_budget)
    raise Cyclic.new("topological sort failed: the graph has a cycle") if counter.total.zero?
    counter.unrank(rank)
  end

  # Returns a linear extension (a valid execution order, from children to
  # parents) sampled uniformly at random from all linear extensions of
  # the graph.  Unlike greedily picking a random zero-indegree node at
  # each step -- which is biased because different prefixes leave
  # different numbers of completions -- this samples each linear
  # extension with exactly equal probability, using exact counts.
  #
  # _random_ is the random number generator to use, responding to
  # #rand like Random and Random::Formatter-compatible objects.
  #
  # TSort::Cyclic is raised if the graph has a cycle.
  # TSort::StateBudgetExceeded is raised when the state budget is
  # exceeded.
  #
  #   graph = G.new({1=>[2, 3], 2=>[4], 3=>[4], 4=>[]})
  #   p graph.linear_extension_sample(random: Random.new(42))
  #   #=> [4, 2, 3, 1] or [4, 3, 2, 1], each with probability 1/2
  #
  def linear_extension_sample(random: Random.new, state_budget: DEFAULT_STATE_BUDGET)
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.linear_extension_sample(each_node, each_child, random: random, state_budget: state_budget)
  end

  # The class-method version of #linear_extension_sample.
  # The graph is represented by _each_node_ and _each_child_.
  def self.linear_extension_sample(each_node, each_child, random: Random.new, state_budget: DEFAULT_STATE_BUDGET)
    counter = LinearExtensionCounter.new(each_node, each_child, state_budget)
    raise Cyclic.new("topological sort failed: the graph has a cycle") if counter.total.zero?
    counter.sample(random)
  end

  # Counts linear extensions of a directed acyclic graph by dynamic
  # programming over subsets of nodes, and derives ranking, unranking and
  # uniform sampling from the exact counts.  A state is the bitmask of
  # nodes already placed (executed); a node can be placed once all of its
  # children are placed.  All arithmetic uses Ruby Integers, so counts
  # are exact bignums.
  class LinearExtensionCounter # :nodoc:
    def initialize(each_node, each_child, state_budget)
      @state_budget = state_budget
      @nodes = []
      each_node.call {|node| @nodes << node }
      @index = {}
      @nodes.each_with_index {|node, i| @index[node] = i }
      size = @nodes.size
      @prereq = Array.new(size, 0)
      @nodes.each_with_index do |node, i|
        each_child.call(node) do |child|
          child_index = @index[child]
          raise ArgumentError, "child node not in graph: #{child.inspect}" unless child_index
          @prereq[i] |= 1 << child_index
        end
      end
      @full = (1 << size) - 1
      @memo = {}
      @state_count = 0
    end

    # Number of subset states explored so far.
    attr_reader :state_count

    def total
      count(0)
    end

    def rank(order)
      nodes = order.to_a
      unless nodes.size == @nodes.size
        raise ArgumentError, "not a permutation of the graph nodes: #{order.inspect}"
      end
      done = 0
      rank = 0
      nodes.each do |node|
        i = @index[node]
        raise ArgumentError, "unknown node in order: #{node.inspect}" unless i
        bit = 1 << i
        unless (done & bit).zero? && (@prereq[i] & ~done).zero?
          raise ArgumentError, "not a valid linear extension: #{order.inspect}"
        end
        each_available(done) do |j, jbit|
          break if j >= i
          rank += count(done | jbit)
        end
        done |= bit
      end
      rank
    end

    def unrank(rank)
      total = self.total
      unless rank.is_a?(Integer) && 0 <= rank && rank < total
        raise ArgumentError, "rank out of range 0...#{total}: #{rank.inspect}"
      end
      done = 0
      order = []
      until done == @full
        each_available(done) do |i, bit|
          c = count(done | bit)
          if rank < c
            order << @nodes[i]
            done |= bit
            break
          end
          rank -= c
        end
      end
      order
    end

    def sample(random)
      done = 0
      order = []
      until done == @full
        r = random.rand(count(done))
        each_available(done) do |i, bit|
          c = count(done | bit)
          if r < c
            order << @nodes[i]
            done |= bit
            break
          end
          r -= c
        end
      end
      order
    end

    private

    def count(done)
      return 1 if done == @full
      return @memo[done] if @memo.key?(done)
      @state_count += 1
      if @state_count > @state_budget
        raise StateBudgetExceeded,
          "state budget exceeded: more than #{@state_budget} subset states"
      end
      sum = 0
      each_available(done) {|_i, bit| sum += count(done | bit) }
      @memo[done] = sum
    end

    def each_available(done)
      i = 0
      size = @nodes.size
      while i < size
        bit = 1 << i
        yield i, bit if (done & bit).zero? && (@prereq[i] & ~done).zero?
        i += 1
      end
    end
  end
  private_constant :LinearExtensionCounter

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
