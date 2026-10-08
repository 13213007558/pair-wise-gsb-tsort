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

  # Counts Eulerian edge-index sequences starting at +start+ whose first
  # edge is +edges[first_edge]+ by exhaustive backtracking.  Used as an
  # independent oracle for TSort.count_eulerian_circuits.
  def brute_force_eulerian_circuits(edges, start, first_edge)
    tails = edges.map {|e| e[0] }
    heads = edges.map {|e| e[1] }
    used = Array.new(edges.size, false)
    used[first_edge] = true
    count = 0
    walk = lambda do |node, remaining|
      if remaining.zero?
        count += 1 if node == start
        next
      end
      edges.each_index {|i|
        next if used[i] || tails[i] != node
        used[i] = true
        walk.call(heads[i], remaining - 1)
        used[i] = false
      }
    end
    walk.call(heads[first_edge], edges.size - 1)
    count
  end

  def test_s_count_eulerian_circuits_basic
    edges = [[1, 2], [2, 1]]
    assert_equal(1, TSort.count_eulerian_circuits([1, 2], edges, start: 1))
    assert_equal(brute_force_eulerian_circuits(edges, 1, 0),
                 TSort.count_eulerian_circuits([1, 2], edges, start: 1))

    edges = [[1, 2], [2, 3], [3, 1]]
    assert_equal(1, TSort.count_eulerian_circuits([1, 2, 3], edges, start: 1))
  end

  def test_s_count_eulerian_circuits_parallel_edges
    edges = [[:a, :b], [:a, :b], [:b, :a], [:b, :a]]
    assert_equal(2, TSort.count_eulerian_circuits([:a, :b], edges, start: :a))
    assert_equal(2, brute_force_eulerian_circuits(edges, :a, 0))
  end

  def test_s_count_eulerian_circuits_self_loops
    edges = [[1, 1], [1, 1], [1, 2], [2, 1]]
    assert_equal(brute_force_eulerian_circuits(edges, 1, 0),
                 TSort.count_eulerian_circuits([1, 2], edges, start: 1))
    assert_equal(2, TSort.count_eulerian_circuits([1, 2], edges, start: 1))

    # a single loop on a single node
    assert_equal(1, TSort.count_eulerian_circuits([1], [[1, 1]], start: 1))
  end

  def test_s_count_eulerian_circuits_against_brute_force
    graphs = [
      [[1, 2], [[1, 2], [2, 1]]],
      [[1, 2, 3], [[1, 2], [2, 3], [3, 1]]],
      [[1, 2], [[1, 2], [1, 2], [2, 1], [2, 1]]],
      [[1, 2], [[1, 1], [1, 2], [2, 1], [2, 2]]],
      [[1, 2, 3], [[1, 1], [1, 2], [2, 3], [3, 1], [3, 2], [2, 1]]],
      [[1, 2, 3], [[1, 2], [1, 2], [2, 3], [2, 3], [3, 1], [3, 1]]],
      [[1, 2, 3], [[1, 2], [2, 1], [2, 3], [3, 2], [1, 3], [3, 1]]],
      [[1, 2], [[1, 1], [1, 1], [1, 1]]],
    ]
    graphs.each {|nodes, edges|
      start = edges[0][0]
      assert_equal(brute_force_eulerian_circuits(edges, start, 0),
                   TSort.count_eulerian_circuits(nodes, edges, start: start),
                   "mismatch for #{edges.inspect}")
      # also with a fixed first edge that is not the first in the list
      last = edges.size - 1
      start = edges[last][0]
      assert_equal(brute_force_eulerian_circuits(edges, start, last),
                   TSort.count_eulerian_circuits(nodes, edges,
                                                 start: start,
                                                 first_edge: last),
                   "mismatch for #{edges.inspect} with first_edge=#{last}")
    }
  end

  def test_s_count_eulerian_circuits_unbalanced
    edges = [[1, 2], [2, 3]]
    assert_equal(0, TSort.count_eulerian_circuits([1, 2, 3], edges, start: 1))
  end

  def test_s_count_eulerian_circuits_disconnected
    edges = [[1, 2], [2, 1], [3, 4], [4, 3]]
    assert_equal(0, TSort.count_eulerian_circuits([1, 2, 3, 4], edges, start: 1))
  end

  def test_s_count_eulerian_circuits_empty_graph
    assert_equal(0, TSort.count_eulerian_circuits([], [], start: 1))
    assert_equal(1, TSort.count_eulerian_circuits([1], [], start: 1))
    assert_equal(1, TSort.count_eulerian_circuits([1, 2, 3], [], start: 2))
    assert_equal(0, TSort.count_eulerian_circuits([1, 2, 3], [], start: 4))
    assert_raise(ArgumentError) {
      TSort.count_eulerian_circuits([1], [], start: 1, first_edge: 1)
    }
  end

  def test_s_count_eulerian_circuits_isolated_nodes
    edges = [[1, 2], [2, 1]]
    assert_equal(1, TSort.count_eulerian_circuits([1, 2, 3, 4], edges, start: 1))
  end

  def test_s_count_eulerian_circuits_first_edge_validation
    edges = [[1, 2], [2, 1]]
    assert_raise(ArgumentError) {
      TSort.count_eulerian_circuits([1, 2], edges, start: 1, first_edge: 2)
    }
    assert_raise(ArgumentError) {
      TSort.count_eulerian_circuits([1, 2], edges, start: 1, first_edge: -1)
    }
    assert_raise(ArgumentError) {
      TSort.count_eulerian_circuits([1, 2], edges, start: 1, first_edge: 1)
    }
  end

  def test_s_count_eulerian_circuits_conversion_factors
    # theta graph: two internally-disjoint paths of length 2 from a to b
    nodes = [:a, :b, :c, :d]
    edges = [[:a, :c], [:c, :b], [:a, :d], [:d, :b], [:b, :a], [:b, :a]]
    n = TSort.count_eulerian_circuits(nodes, edges, start: :a)
    m = edges.size
    outdeg_start = 2
    assert_equal(brute_force_eulerian_circuits(edges, :a, 0), n)
    # circuits starting at :a with any first edge
    any_first = edges.each_index.select {|i| edges[i][0] == :a }.sum {|i|
      brute_force_eulerian_circuits(edges, :a, i)
    }
    assert_equal(n * outdeg_start, any_first)
    # n itself is the number of cyclic orders (rotation classes)
    assert_equal(any_first / outdeg_start, n)
    # linear sequences with any start: n * m in a single weak component
    total = nodes.sum {|v|
      edges.each_index.select {|i| edges[i][0] == v }.sum {|i|
        brute_force_eulerian_circuits(edges, v, i)
      }
    }
    assert_equal(n * m, total)
  end

  def test_s_count_eulerian_circuits_large
    # 5 parallel edges each way between two nodes:
    # t(a) = 5, result = 5 * 4! * 4! = 2880.
    edges = ([[:a, :b]] * 5) + ([[:b, :a]] * 5)
    assert_equal(5 * 24 * 24,
                 TSort.count_eulerian_circuits([:a, :b], edges, start: :a))
  end
end
