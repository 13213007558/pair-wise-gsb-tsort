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

  # Returns a minimum chain cover of the directed acyclic graph together with
  # a maximum antichain of the same size, by Dilworth's theorem.
  #
  # A chain is ordered from child to parent, as in #tsort. Consecutive nodes
  # in a chain only need to be comparable, so they may be connected by an
  # indirect path. Each such witness path is included in the +paths+ entry for
  # the chain. A witness path may contain nodes belonging to another chain.
  #
  # The result has the following keys:
  #
  # * +:chains+ - an array of chains. Each chain is a hash with +:nodes+ and
  #   +:paths+. Every graph node occurs in exactly one +:nodes+ array.
  # * +:antichain+ - a maximum set of pairwise incomparable nodes.
  # * +:size+ - the number of chains, which equals the antichain size.
  #
  # The size describes structural parallelism in the partial order. It is not
  # a guaranteed achievable thread count when execution has resource or other
  # constraints.
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
  #   graph = G.new(1=>[2, 3], 2=>[4], 3=>[4], 4=>[])
  #   graph.minimum_chain_cover
  #   #=> {:chains=>[{:nodes=>[4, 2, 1], :paths=>[[4, 2], [2, 1]]},
  #          {:nodes=>[3], :paths=>[]}],
  #       :antichain=>[2, 3],
  #       :size=>2}
  #
  def minimum_chain_cover
    each_node = method(:tsort_each_node)
    each_child = method(:tsort_each_child)
    TSort.minimum_chain_cover(each_node, each_child)
  end

  # Returns a minimum chain cover for the graph represented by _each_node_ and
  # _each_child_. See #minimum_chain_cover for the result shape.
  #
  # _each_node_ should have a +call+ method which yields each node in the
  # graph. _each_child_ should have a +call+ method which takes a node and
  # yields each direct child node.
  #
  # If there is a cycle, TSort::Cyclic is raised.
  #
  def self.minimum_chain_cover(each_node, each_child)
    nodes = []
    node_ids = {}
    direct_children = []
    queue = []

    add_node = lambda do |node|
      unless node_ids.include?(node)
        id = nodes.length
        node_ids[node] = id
        nodes << node
        direct_children << []
        queue << id
      end
      node_ids[node]
    end

    each_node.call {|node| add_node.call(node) }

    until queue.empty?
      id = queue.shift
      node = nodes[id]
      each_child.call(node) do |child|
        child_id = add_node.call(child)
        direct_children[id] << child_id
      end
    end

    node_count = nodes.length
    return {chains: [], antichain: [], size: 0} if node_count.zero?

    indegree = Array.new(node_count, 0)
    direct_children.each do |children|
      children.each {|child_id| indegree[child_id] += 1 }
    end

    topological_order = []
    ready = []
    indegree.each_with_index do |degree, id|
      ready << id if degree.zero?
    end

    until ready.empty?
      id = ready.pop
      topological_order << id
      direct_children[id].each do |child_id|
        indegree[child_id] -= 1
        ready << child_id if indegree[child_id].zero?
      end
    end

    unless topological_order.length == node_count
      raise Cyclic.new("minimum chain cover failed: graph is not acyclic")
    end

    reachable = Array.new(node_count, 0)
    topological_order.reverse_each do |id|
      direct_children[id].each do |child_id|
        reachable[id] |= (1 << child_id) | reachable[child_id]
      end
    end

    matched_right = Array.new(node_count)
    matched_left = Array.new(node_count)

    augment = lambda do |left_id, visited_right|
      node_count.times do |right_id|
        next unless reachable[left_id][right_id] == 1
        next unless visited_right[right_id].nil?
        visited_right[right_id] = true

        if matched_right[right_id].nil? ||
           augment.call(matched_right[right_id], visited_right)
          matched_right[right_id] = left_id
          matched_left[left_id] = right_id
          return true
        end
      end
      false
    end

    node_count.times do |left_id|
      augment.call(left_id, {})
    end

    reachable_left = Array.new(node_count, false)
    reachable_right = Array.new(node_count, false)
    alternating_queue = []

    node_count.times do |id|
      if matched_left[id].nil?
        reachable_left[id] = true
        alternating_queue << id
      end
    end

    until alternating_queue.empty?
      left_id = alternating_queue.shift
      node_count.times do |right_id|
        next unless reachable[left_id][right_id] == 1
        next if right_id == matched_left[left_id]
        next if reachable_right[right_id]

        reachable_right[right_id] = true
        next_left_id = matched_right[right_id]
        if next_left_id && !reachable_left[next_left_id]
          reachable_left[next_left_id] = true
          alternating_queue << next_left_id
        end
      end
    end

    antichain_ids = node_count.times.select do |id|
      reachable_left[id] && !reachable_right[id]
    end

    has_predecessor = Array.new(node_count, false)
    matched_right.each_with_index do |left_id, right_id|
      has_predecessor[right_id] = true if left_id
    end

    chain_ids = node_count.times.reject {|id| has_predecessor[id]}.map do |head_id|
      chain = []
      id = head_id
      while id
        chain << id
        id = matched_left[id]
      end
      chain
    end

    chains = chain_ids.map do |forward_chain|
      {
        nodes: forward_chain.reverse.map {|id| nodes[id]},
        paths: forward_chain.reverse.each_cons(2).map do |child_id, parent_id|
          chain_path(parent_id, child_id, direct_children)
                    .map {|id| nodes[id]}
        end
      }
    end

    {
      chains: chains,
      antichain: antichain_ids.map {|id| nodes[id]},
      size: chains.length
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

  def self.chain_path(parent_id, child_id, direct_children)
    parents = {parent_id => nil}
    queue = [parent_id]

    until queue.empty?
      id = queue.shift
      direct_children[id].each do |candidate_id|
        next if parents.include?(candidate_id)

        parents[candidate_id] = id
        if candidate_id == child_id
          path = []
          current_id = child_id
          while current_id
            path << current_id
            current_id = parents[current_id]
          end
          return path
        end
        queue << candidate_id
      end
    end
  end
  private_class_method :chain_path

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
