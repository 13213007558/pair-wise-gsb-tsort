# frozen_string_literal: true

require 'tsort'
require 'test/unit'

class TSortHash < Hash # :nodoc:
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

class TSortArray < Array # :nodoc:
  include TSort
  alias tsort_each_node each_index
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

class TSortCountedHash < Hash # :nodoc:
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    @child_calls ||= 0
    @child_calls += 1
    fetch(node).each(&block)
  end
  def child_calls; @child_calls || 0; end
end

class TSortTest < Test::Unit::TestCase # :nodoc:
  def test_dag
    h = TSortHash[{1=>[2, 3], 2=>[3], 3=>[]}]
    assert_equal([3, 2, 1], h.tsort)
    assert_equal([[3], [2], [1]], h.strongly_connected_components)
  end

  def test_cycle
    h = TSortHash[{1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}]
    assert_equal([[4], [2, 3], [1]],
      h.strongly_connected_components.map {|nodes| nodes.sort})
    assert_raise(TSort::Cyclic) { h.tsort }
  end

  def test_array
    a = TSortArray[[1], [0], [0], [2]]
    assert_equal([[0, 1], [2], [3]],
      a.strongly_connected_components.map {|nodes| nodes.sort})

    a = TSortArray[[], [0]]
    assert_equal([[0], [1]],
      a.strongly_connected_components.map {|nodes| nodes.sort})
  end

  def test_s_tsort
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([4, 2, 3, 1], TSort.tsort(each_node, each_child))
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    assert_raise(TSort::Cyclic) { TSort.tsort(each_node, each_child) }
  end

  def test_s_tsort_each
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.tsort_each(each_node, each_child) {|n| r << n }
    assert_equal([4, 2, 3, 1], r)

    r = TSort.tsort_each(each_node, each_child).map {|n| n.to_s }
    assert_equal(['4', '2', '3', '1'], r)
  end

  def test_s_strongly_connected_components
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([[4], [2], [3], [1]],
                 TSort.strongly_connected_components(each_node, each_child))
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    assert_equal([[4], [2, 3], [1]],
                 TSort.strongly_connected_components(each_node, each_child))
  end

  def test_s_each_strongly_connected_component
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.each_strongly_connected_component(each_node, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2], [3], [1]], r)
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    r = []
    TSort.each_strongly_connected_component(each_node, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2, 3], [1]], r)

    r = TSort.each_strongly_connected_component(each_node, each_child).map {|scc|
      scc.map(&:to_s)
    }
    assert_equal([['4'], ['2', '3'], ['1']], r)
  end

  def test_s_each_strongly_connected_component_from
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.each_strongly_connected_component_from(1, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2, 3], [1]], r)

    r = TSort.each_strongly_connected_component_from(1, each_child).map {|scc|
      scc.map(&:to_s)
    }
    assert_equal([['4'], ['2', '3'], ['1']], r)
  end

  def test_each_cycle
    h = TSortHash[{1=>[2], 2=>[3], 3=>[1, 2], 4=>[]}]
    assert_equal([[1, 2, 3], [2, 3]], h.each_cycle.to_a)
    assert_equal(nil, h.each_cycle { })
  end

  def test_cycles
    assert_equal([], TSortHash[{1=>[2], 2=>[], 3=>[1]}].cycles)
    assert_equal([[1]], TSortHash[{1=>[1]}].cycles)
    h = TSortHash[{1=>[2], 2=>[3], 3=>[1, 2]}]
    assert_equal([[1, 2, 3], [2, 3]], h.cycles)
  end

  def test_cycle_has_no_repeated_node
    h = TSortHash[{1=>[2, 3], 2=>[1, 3], 3=>[1, 2]}]
    h.cycles.each {|cycle|
      assert_equal(cycle.length, cycle.uniq.length,
                   "cycle #{cycle.inspect} repeats a node")
    }
  end

  def test_cycle_rotation_is_identical_but_reversal_is_distinct
    # Each elementary directed cycle of the complete directed graph on 3
    # nodes is reported once: cyclic rotations (1,2,3)/(2,3,1)/(3,1,2)
    # collapse to one result, while (1,3,2) is a different directed cycle
    # because its edges point the other way around.
    h = TSortHash[{1=>[2, 3], 2=>[1, 3], 3=>[1, 2]}]
    assert_equal([[1, 2], [1, 2, 3], [1, 3], [1, 3, 2], [2, 3]],
                 h.cycles)
    assert_equal([[1, 2, 3], [1, 3, 2]],
                 h.cycles.select {|cycle| cycle.length == 3 })
  end

  def test_cycle_starts_with_earliest_enumerated_node
    # Even when nodes are first encountered in a different order, the
    # representative of each cycle starts with the node enumerated first
    # by tsort_each_node (3 here, then 2, then 1).
    h = TSortHash[{3=>[1, 2], 2=>[1, 3], 1=>[2, 3]}]
    order = [3, 2, 1]
    assert(h.cycles.all? {|cycle| order.index(cycle.first) == cycle.map {|n| order.index(n) }.min})
    assert_equal([3, 1, 2], h.cycles.find {|cycle| cycle.length == 3 })
  end

  def test_each_cycle_fixed_order
    hash = {1=>[2, 3], 2=>[1, 3], 3=>[1, 2]}
    first = TSortHash[hash].cycles
    second = TSortHash[hash].cycles
    assert_equal(first, second)
    # Depth-first order induced by tsort_each_child.
    assert_equal([[1, 2], [1, 2, 3], [1, 3], [1, 3, 2], [2, 3]], first)
  end

  def test_each_cycle_is_lazy
    h = TSortCountedHash[{1=>[2], 2=>[1], 3=>[4], 4=>[5], 5=>[3]}]
    enumerator = h.each_cycle
    assert_instance_of(Enumerator, enumerator)
    assert_equal(0, h.child_calls,
                 "creating the Enumerator must not traverse the graph")
    assert_equal([1, 2], enumerator.first)
    # The first result is the small 2-node cycle; the disjoint 3-node
    # cycle has not been completed by the time the first result arrives,
    # so enumerating all cycles up-front would produce many more cycles
    # than this single result.
    assert_equal([[1, 2]], h.each_cycle.take(1))
    assert_equal([[1, 2], [3, 4, 5]], h.each_cycle.first(2))
  end

  def test_each_cycle_does_not_explode_unexplored_part
    # The node :bomb raises as soon as its children are inspected.  It is
    # enumerated after the real cycle, so taking only the first result
    # must not touch its edges; an eager implementation would explode.
    wrapper = Object.new
    graph = {1=>[2], 2=>[1], :bomb=>[:bomb]}
    wrapper.define_singleton_method(:tsort_each_node) do |&block|
      graph.each_key(&block)
    end
    wrapper.define_singleton_method(:tsort_each_child) do |node, &block|
      raise "reached bomb" if node == :bomb
      graph[node].each(&block)
    end
    wrapper.extend(TSort)
    assert_equal([1, 2], wrapper.each_cycle.first)
  end

  def test_two_cycles_sharing_a_vertex_but_no_edge
    # The cycle 1->2->1 and 1->3->1 share node 1 but no edge.  A blocked
    # node left over from the first cycle must not suppress the second.
    h = TSortHash[{1=>[2, 3], 2=>[1], 3=>[1]}]
    assert_equal([[1, 2], [1, 3]], h.cycles)
  end

  def test_two_cycles_sharing_vertices_but_no_edge
    # The two elementary cycles 1->2->4->1 and 1->3->4->1 share vertices
    # 1 and 4 but no edge.  The branch through 3 finds its closing edge only
    # via 4, which a naive blocked-set implementation can leave blocked
    # after the branch through 2; both cycles must still be reported.
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[1]}]
    assert_equal([[1, 2, 4], [1, 3, 4]], h.cycles.sort)
  end

  def test_parallel_edges_unique
    # Two parallel edges from 2 to 1: the cycle is reported once by
    # default, as the caller chooses to identify them.
    h = TSortHash[{1=>[2, 2], 2=>[1]}]
    assert_equal([[1, 2]], h.cycles)
    assert_equal([[1, 2]], h.each_cycle(unique: true).to_a)
  end

  def test_parallel_edges_keep_identity
    # The same directed cycle is reported once per parallel edge, in the
    # fixed child order.
    h = TSortHash[{1=>[2, 2], 2=>[1]}]
    assert_equal([[1, 2], [1, 2]], h.each_cycle(unique: false).to_a)
    h2 = TSortHash[{1=>[2, 2, 2], 2=>[1, 1]}]
    assert_equal([[1, 2]] * 6, h2.each_cycle(unique: false).to_a)
  end

  def test_parallel_self_loops
    h = TSortHash[{1=>[1, 1, 2], 2=>[1]}]
    assert_equal([[1], [1, 2]], h.cycles)
    assert_equal([[1], [1], [1, 2]], h.each_cycle(unique: false).to_a)
  end

  def test_s_each_cycle
    g = {1=>[2], 2=>[3], 3=>[1, 2], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([[1, 2, 3], [2, 3]],
                 TSort.each_cycle(each_node, each_child).to_a)
    r = []
    TSort.each_cycle(each_node, each_child) {|cycle| r << cycle }
    assert_equal([[1, 2, 3], [2, 3]], r)
  end

  def test_s_cycles
    g = {1=>[2, 2], 2=>[1]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([[1, 2]], TSort.cycles(each_node, each_child))
    assert_equal([[1, 2], [1, 2]],
                 TSort.cycles(each_node, each_child, unique: false))
  end
end
