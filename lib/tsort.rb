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

# An updatable topological view of a directed graph.
#
# TSort::UpdatableTopoView maintains an explicit topological ordering of
# a graph that changes over time: edges and nodes can be added and
# removed one at a time, and the ordering is repaired locally after each
# update instead of being recomputed from scratch.  It is meant for
# long-lived services that keep a dependency graph and cannot afford to
# re-sort the whole graph (and disturb every node's position) on every
# single edge update.
#
# An edge added with +add_edge(u, v)+ means "u must appear before v".
# Nodes are arbitrary objects; equality is defined by +eql?+ and +hash+,
# as in the rest of TSort.
#
#   view = TSort::UpdatableTopoView.new([:parse, :compile, :link, :pack])
#   view.add_edge(:parse, :compile)   # => true
#   view.add_edge(:compile, :link)    # => true
#   view.order                        # => [:parse, :compile, :link, :pack]
#   view.add_edge(:link, :parse)      # => [:link, :parse, :compile, :link]
#   view.order                        # => [:parse, :compile, :link, :pack] (unchanged)
#
# == Stability
#
# "Stability" is defined precisely as follows.  Let < be the relative
# order of nodes before an update and <' the relative order after it.
#
# * remove_node and remove_edge never reorder anything: for every pair
#   of surviving nodes x and y, x < y implies x <' y.
# * add_edge(u, v) with u < v changes nothing.
# * add_edge(u, v) with v < u repairs the ordering with the
#   Pearce--Kelly algorithm.  Let R be the nodes between v and u
#   (inclusive) in the old ordering, F the nodes of R reachable from v,
#   and B the nodes of R that can reach u.  The update moves B (kept in
#   its old relative order) in front of F (also kept in its old relative
#   order) inside the slots previously occupied by B and F.  Then:
#
#   1. nodes outside R keep their exact positions;
#   2. nodes of R that are in neither F nor B keep their exact
#      positions;
#   3. the relative order inside F and inside B is preserved;
#   4. consequently a pair x < y can only be inverted (y <' x) when x
#      or y belongs to F or B, that is, when the update actually
#      inspected x or y; two uninspected nodes never change their
#      relative order.
#
#   Every inversion between F and B is unavoidable: each b in B reaches
#   u and each f in F is reached from v, so b <' f holds in every valid
#   ordering once the edge u -> v exists.
#
# == Locality
#
# Updates never scan the whole graph.  Each mutating method records the
# nodes it actually examined in #last_inspected:
#
# * add_edge examines only F and B (just the two endpoints when no
#   reordering is needed),
# * remove_edge examines only the two endpoints,
# * remove_node examines only the node and its former neighbors.
#
# (Rewriting position indexes after a node is spliced out of the
# ordering is index bookkeeping, not graph inspection, and is therefore
# not counted in #last_inspected.)
#
# == References
#
# D. J. Pearce, P. H. J. Kelly, "A Dynamic Topological Sort Algorithm
# for Directed Acyclic Graphs", <em>ACM Journal of Experimental
# Algorithmics</em>, Vol. 11, 2006.
#
class TSort::UpdatableTopoView
  # Creates a view over _nodes_, which also fixes the initial ordering.
  # The graph starts without edges; duplicate nodes are rejected.
  def initialize(nodes = [])
    order = nodes.dup
    unless order.uniq.size == order.size
      raise ArgumentError, "duplicate nodes: #{nodes.inspect}"
    end
    @order = order
    @pos = {}             # node => index in @order
    @succ = {}            # node => array of successors
    @pred = {}            # node => array of predecessors
    @order.each_with_index do |node, i|
      @pos[node] = i
      @succ[node] = []
      @pred[node] = []
    end
    @last_inspected = [].freeze
  end

  # Returns the current topological ordering as a new array.
  def order
    @order.dup
  end

  # Returns the number of nodes.
  def size
    @order.size
  end

  # Returns true if _node_ is part of the view.
  def include?(node)
    @pos.key?(node)
  end

  # Returns the edges as an array of [from, to] pairs.
  def edges
    result = []
    @succ.each_pair do |u, ws|
      ws.each do |v|
        result << [u, v]
      end
    end
    result
  end

  # Returns the nodes examined by the most recent update.
  # See the "Locality" section of the class documentation.
  def last_inspected
    @last_inspected
  end

  # Adds _node_ at the end of the ordering.
  # Returns true if the node was added, false if it was already present.
  def add_node(node)
    @last_inspected = [node].freeze
    return false if @pos.key?(node)
    @pos[node] = @order.size
    @order << node
    @succ[node] = []
    @pred[node] = []
    true
  end

  # Adds the edge u -> v ("u must appear before v") and repairs the
  # ordering locally if needed.  Unknown nodes are added first, at the
  # end of the ordering.
  #
  # Returns true if the edge is present after the call.  If the edge
  # would close a cycle, the view is left untouched and the cycle is
  # returned instead, as an array of nodes [u, v, ..., u] whose first
  # step is the rejected edge u -> v and whose remaining steps are
  # existing edges.
  def add_edge(u, v)
    add_node(u) unless include?(u)
    add_node(v) unless include?(v)
    if u.eql?(v)
      @last_inspected = [u].freeze
      return [u, u]
    end
    if @succ[u].include?(v)
      @last_inspected = [u, v].freeze
      return true
    end
    iu = @pos[u]
    iv = @pos[v]
    if iu < iv
      # Already ordered; a path v ~> u cannot exist, so no cycle and
      # no reordering.
      @succ[u] << v
      @pred[v] << u
      @last_inspected = [u, v].freeze
      return true
    end
    # v is before u: only nodes between them can be affected.
    # F: nodes reachable from v inside the region, with parent links.
    forward = {v => nil}
    stack = [v]
    cyclic = false
    until stack.empty?
      n = stack.pop
      if n.eql?(u)
        cyclic = true
        break
      end
      @succ[n].each do |w|
        next if forward.key?(w)
        next if @pos[w] > iu
        forward[w] = n
        stack << w
      end
    end
    if cyclic
      path = [u]
      while (parent = forward[path.first])
        path.unshift(parent)
      end
      @last_inspected = forward.keys.freeze
      return [u, *path]
    end
    # B: nodes that can reach u inside the region.
    backward = {u => true}
    stack = [u]
    until stack.empty?
      n = stack.pop
      @pred[n].each do |w|
        next if backward.key?(w)
        next if @pos[w] < iv
        backward[w] = true
        stack << w
      end
    end
    # Move B in front of F inside the slots they already occupy.
    slots = []
    bs = []
    fs = []
    (iv..iu).each do |i|
      n = @order[i]
      if backward.key?(n)
        slots << i
        bs << n
      elsif forward.key?(n)
        slots << i
        fs << n
      end
    end
    (bs + fs).each_with_index do |n, k|
      @order[slots[k]] = n
      @pos[n] = slots[k]
    end
    @succ[u] << v
    @pred[v] << u
    @last_inspected = (forward.keys | backward.keys).freeze
    true
  end

  # Removes the edge u -> v.  The ordering is left untouched.
  # Returns true if the edge existed, false otherwise.
  def remove_edge(u, v)
    @last_inspected = [u, v].freeze
    ws = @succ[u]
    return false unless ws && ws.include?(v)
    ws.delete(v)
    @pred[v].delete(u)
    true
  end

  # Removes _node_ and its incident edges.  The relative order of the
  # remaining nodes is preserved exactly.
  # Returns true if the node existed, false otherwise.
  def remove_node(node)
    @last_inspected = [node].freeze
    return false unless @pos.key?(node)
    inspected = [node]
    @succ[node].each do |w|
      @pred[w].delete(node)
      inspected << w
    end
    @pred[node].each do |w|
      @succ[w].delete(node)
      inspected << w
    end
    @succ.delete(node)
    @pred.delete(node)
    i = @pos.delete(node)
    @order.delete_at(i)
    # Re-index the tail; index bookkeeping, not graph inspection.
    (i...@order.size).each do |k|
      @pos[@order[k]] = k
    end
    @last_inspected = inspected.uniq.freeze
    true
  end
end
