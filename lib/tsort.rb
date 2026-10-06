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

  # Result of an incremental TSort::TopologicalView update.
  class TopologicalUpdateResult
    # Returns the view which performed the update.
    attr_reader :view

    # Returns +:add_edge+, +:delete_edge+, or +:delete_node+.
    attr_reader :type

    # Returns whether an edge was added.
    attr_reader :added

    # Returns whether an edge was removed.
    attr_reader :removed

    # Returns whether the stored order was changed.
    attr_reader :reordered

    # Returns whether the rejected edge would create a cycle.
    attr_reader :cyclic

    # Returns the concrete cycle path for a rejected edge.
    attr_reader :cycle_path

    # Returns nodes whose graph membership or position was changed.
    attr_reader :affected_nodes

    # Returns nodes visited by the local forward reachability search.
    attr_reader :searched_nodes

    # Returns the old ordered interval bounded by the edge endpoints.
    attr_reader :span_nodes

    # Returns nodes examined while performing the local update, including
    # neighbors whose edge lists were read.
    attr_reader :checked_nodes

    def initialize(view, type, added: false, removed: false, reordered: false,
                   cyclic: false, cycle_path: nil, affected_nodes: [],
                   searched_nodes: [], span_nodes: [], checked_nodes: nil)
      @view = view
      @type = type
      @added = added
      @removed = removed
      @reordered = reordered
      @cyclic = cyclic
      @cycle_path = cycle_path && cycle_path.dup
      @affected_nodes = affected_nodes.dup
      @searched_nodes = searched_nodes.dup
      @span_nodes = span_nodes.dup
      @checked_nodes = (checked_nodes || span_nodes).dup
      freeze
    end

    # Returns true when the update was applied.
    def success?
      !cyclic
    end

    alias cyclic? cyclic
  end

  # A mutable directed graph with an incrementally maintained topological view.
  #
  # As in the rest of TSort, an edge goes from a parent to one of its
  # children. The stored order is children before parents.
  #
  # The initial order must contain each node exactly once and must be a
  # topological order of the initial edges. Edge and node deletion never move a
  # surviving node. Adding an edge which is already satisfied also leaves the
  # order unchanged.
  #
  # When adding parent -> child moves nodes, the affected interval starts at
  # parent and ends at the latest old-order node reachable from child. Nodes
  # outside that interval keep their exact position. Inside it, the new order
  # is the lexicographically smallest topological order according to the old
  # order: repeatedly keep the earliest old-order node whose interval children
  # have already been emitted. This means the first unavoidable difference, and
  # then every following difference, is delayed as far as possible.
  #
  # * nodes outside the interval keep their position;
  # * within the interval, the earliest available old-order node is retained
  #   at each position;
  # * edge deletion and node deletion preserve the relative order of all
  #   surviving nodes.
  #
  # If parent -> child would create a cycle, #add_edge returns a result whose
  # #cyclic? is true and whose #cycle_path is the concrete path. The graph and
  # order are left unchanged.
  #
  #   view = TSort::TopologicalView.new([3, 2, 1, 4],
  #                                     {1 => [2, 3], 2 => [3]})
  #   view.add_edge(4, 1)
  #   view.to_a #=> [3, 2, 1, 4]
  #
  class TopologicalView
    include TSort

    # Creates a view from an initial topological node order and optional
    # adjacency hash mapping parents to their children.
    def initialize(order, edges = nil)
      nodes = order.to_a
      @rank = {}
      nodes.each_with_index do |node, index|
        if @rank.key?(node)
          raise ArgumentError, "duplicate initial node: #{node.inspect}"
        end
        @rank[node] = index + 1
      end

      @forward = {}
      @backward = {}
      nodes.each do |node|
        @forward[node] = {}
        @backward[node] = {}
      end

      if edges
        edges.each do |parent, children|
          unless @rank.key?(parent)
            raise ArgumentError, "unknown node: #{parent.inspect}"
          end
          Array(children).uniq.each do |child|
            unless @rank.key?(child)
              raise ArgumentError, "unknown node: #{child.inspect}"
            end
            if @rank[parent] <= @rank[child]
              raise ArgumentError,
                    "initial order is not topologically sorted: #{parent.inspect} -> #{child.inspect}"
            end
          end
        end

        edges.each do |parent, children|
          Array(children).uniq.each do |child|
            @forward[parent][child] = true
            @backward[child][parent] = true
          end
        end
      end

      @previous = {}
      @next = {}
      nodes.each_cons(2) do |previous, node|
        @previous[node] = previous
        @next[previous] = node
      end
      @head = nodes.first
      @last_result = nil
    end

    # Returns the current topological order as an array.
    def to_a
      result = []
      node = @head
      while node
        result << node
        node = @next[node]
      end
      result
    end

    # Iterates over the current topological order.
    def each(&block)
      return to_enum(__method__) unless block_given?
      to_a.each(&block)
      nil
    end

    # Returns the number of nodes in the view.
    def size
      @rank.size
    end

    # Returns whether the view contains _node_.
    def include?(node)
      @rank.key?(node)
    end

    alias node? include?

    # Returns whether an edge exists from _parent_ to _child_.
    def edge?(parent, child)
      @rank.key?(parent) && @rank.key?(child) && @forward[parent].key?(child)
    end

    # Returns the result of the most recent update.
    attr_reader :last_result

    # Adds an edge from _parent_ to _child_.
    #
    # The returned TSort::TopologicalUpdateResult records whether the edge was
    # added, whether the order changed, and which nodes the local update
    # examined. A cyclic edge is rejected and the view remains usable.
    def add_edge(parent, child)
      ensure_node!(parent)
      ensure_node!(child)

      if @forward[parent].key?(child)
        return finish_update(TopologicalUpdateResult.new(
          self, :add_edge,
          affected_nodes: [parent, child],
          checked_nodes: [parent]
        ))
      end

      if parent.equal?(child)
        return cyclic_update(parent, child, {parent => nil}, [parent])
      end

      if @rank[parent] > @rank[child]
        @forward[parent][child] = true
        @backward[child][parent] = true
        return finish_update(TopologicalUpdateResult.new(
          self, :add_edge, added: true,
          affected_nodes: [parent, child],
          checked_nodes: [parent]
        ))
      end

      descendants, parents, searched = forward_search(child, @rank[parent], nil)
      if parents.key?(parent)
        return cyclic_update(parent, child, parents, searched)
      end

      rightmost = descendants.keys.max_by { |node| @rank[node] }
      span = ordered_between(parent, rightmost)
      @forward[parent][child] = true
      @backward[child][parent] = true
      reordered, checked = stable_reorder(span)
      replace_order(span, reordered)

      finish_update(TopologicalUpdateResult.new(
        self, :add_edge, added: true, reordered: true,
        affected_nodes: [parent, child],
        searched_nodes: descendants.keys,
        span_nodes: span,
        checked_nodes: checked
      ))
    end

    # Removes an edge from _parent_ to _child_. The topological order is never
    # changed by edge deletion.
    def delete_edge(parent, child)
      ensure_node!(parent)
      ensure_node!(child)

      unless @forward[parent].key?(child)
        return finish_update(TopologicalUpdateResult.new(
          self, :delete_edge,
          affected_nodes: [parent, child],
          checked_nodes: [parent]
        ))
      end

      @forward[parent].delete(child)
      @backward[child].delete(parent)
      finish_update(TopologicalUpdateResult.new(
        self, :delete_edge, removed: true,
        affected_nodes: [parent, child],
        checked_nodes: [parent, child]
      ))
    end

    # Removes a node and all of its incident edges. The relative order of all
    # surviving nodes is preserved.
    def delete_node(node)
      ensure_node!(node)

      parents = @backward[node].keys
      children = @forward[node].keys
      previous = @previous[node]
      following = @next[node]

      if previous
        @next[previous] = following
      else
        @head = following
      end
      @previous[following] = previous if following

      parents.each { |parent| @forward[parent].delete(node) }
      children.each { |child| @backward[child].delete(node) }
      @forward.delete(node)
      @backward.delete(node)
      @rank.delete(node)
      @previous.delete(node)
      @next.delete(node)

      checked = [node, *parents, *children]
      finish_update(TopologicalUpdateResult.new(
        self, :delete_node, removed: true,
        affected_nodes: checked,
        checked_nodes: checked
      ))
    end

    # Yields each node in topological order, as required by TSort.
    def tsort_each_node(&block)
      to_a.each(&block)
    end

    # Yields each child of _node_, as required by TSort.
    def tsort_each_child(node, &block)
      @forward.fetch(node).each_key(&block)
    end

    private

    def ensure_node!(node)
      unless @rank.key?(node)
        raise ArgumentError, "unknown node: #{node.inspect}"
      end
    end

    def finish_update(result)
      @last_result = result
      result
    end

    def ordered_between(first, last)
      result = []
      node = first
      while node
        result << node
        break if node.equal?(last)
        node = @next[node]
      end
      result
    end

    def cyclic_update(parent, child, parents, checked)
      path = path_from(parents, parent, child)
      finish_update(TopologicalUpdateResult.new(
        self, :add_edge, cyclic: true,
        cycle_path: [parent, *path],
        affected_nodes: [parent, child],
        searched_nodes: checked,
        checked_nodes: checked
      ))
    end

    def forward_search(start, lower, upper)
      parents = {start => nil}
      checked = {start => true}
      stack = [start]

      until stack.empty?
        node = stack.pop
        @forward[node].each_key do |child|
          rank = @rank[child]
          next if rank < lower
          next if upper && rank > upper
          next if parents.key?(child)
          checked[child] = true
          parents[child] = node
          stack << child
        end
      end

      [parents, parents, checked.keys]
    end

    def path_from(parents, target, start)
      path = [target]
      node = target
      while node && !node.equal?(start)
        node = parents[node]
        path << node
      end
      path.reverse
    end

    def stable_reorder(span)
      old_rank = {}
      checked = {}
      span.each { |node| old_rank[node] = @rank[node] }
      span.each { |node| checked[node] = true }
      lower = old_rank[span.first]
      upper = old_rank[span.last]
      remaining_children = {}
      span.each do |node|
        remaining_children[node] = @forward[node].count { |child, _|
          rank = old_rank[child]
          if rank && rank >= lower && rank <= upper
            checked[child] = true
            true
          end
        }
      end

      emitted = {}
      reordered = []
      until reordered.size == span.size
        node = span.find { |candidate|
          !emitted.key?(candidate) && remaining_children[candidate].zero?
        }
        raise Cyclic, "unexpected cycle during local topological update" unless node

        emitted[node] = true
        reordered << node
        @backward[node].each_key do |parent|
          next unless old_rank.key?(parent)
          checked[parent] = true
          remaining_children[parent] -= 1
        end
      end
      [reordered, checked.keys]
    end

    def replace_order(old_segment, new_segment)
      left = @previous[old_segment.first]
      right = @next[old_segment.last]

      if left
        @next[left] = new_segment.first
      else
        @head = new_segment.first
      end

      new_segment.each_cons(2) do |previous, node|
        @previous[node] = previous
        @next[previous] = node
      end

      @previous[new_segment.first] = left
      @next[new_segment.last] = right
      @previous[right] = new_segment.last if right

      lower = left ? @rank[left] : 0
      upper = right ? @rank[right] : @rank[old_segment.last] + 1
      width = upper - lower
      new_segment.each_with_index do |node, index|
        @rank[node] = lower + Rational(width * (index + 1), new_segment.size + 1)
      end
    end
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
        node = component.first
        has_self_loops = false
        each_child.call(node) {|child|
          has_self_loops ||= child.equal?(node) || child.eql?(node)
        }
        raise Cyclic.new("topological sort failed: #{component.inspect}") if has_self_loops
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
end
