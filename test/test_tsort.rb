# frozen_string_literal: true

require 'tsort'
require 'set'
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

class DirectedEdgeGraph # :nodoc:
  include TSort

  def initialize(nodes, edges)
    @nodes = nodes
    @edges = Hash.new {|hash, node| hash[node] = []}
    edges.each {|edge_id, source, destination|
      @edges[source] << [edge_id, destination]
    }
  end

  def tsort_each_node(&block)
    @nodes.each(&block)
  end

  def tsort_each_child(node, &block)
    @edges.fetch(node, []).each {|_, destination| block.call(destination) }
  end

  def tsort_each_edge(node, &block)
    @edges.fetch(node, []).each(&block)
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

  def test_directed_eulerian_circuit_count_self_loop
    graph = DirectedEdgeGraph.new([1], [[:a, 1, 1], [:b, 1, 1], [:c, 1, 1]])

    assert_equal(2, graph.directed_eulerian_circuit_count(1, :a))
    assert_equal(6, graph.directed_eulerian_circuit_count(1, :a) * 3)
  end

  def test_directed_eulerian_circuit_count_parallel_edges
    edges = [
      [:a, 1, 2], [:b, 1, 2],
      [:c, 2, 1], [:d, 2, 1]
    ]
    graph = DirectedEdgeGraph.new([1, 2], edges)

    assert_equal(2, graph.directed_eulerian_circuit_count(1, :a))
    assert_equal(4, graph.directed_eulerian_circuit_count(1, :a) * 2)
    assert_equal(8, graph.directed_eulerian_circuit_count(1, :a) * 4)
  end

  def test_directed_eulerian_circuit_count_self_loop_and_parallel_edges
    edges = [
      [:a, 1, 2], [:b, 1, 2], [:c, 2, 1], [:d, 2, 1],
      [:e, 1, 1], [:f, 2, 2]
    ]
    graph = DirectedEdgeGraph.new([1, 2], edges)

    assert_equal(enumerate_eulerian_circuits(edges, 1, :a).size,
                 graph.directed_eulerian_circuit_count(1, :a))
  end

  def test_directed_eulerian_circuit_count_matches_enumeration
    cases = [
      [[1], [[:a, 1, 1]]],
      [[1], [[:a, 1, 1], [:b, 1, 1]]],
      [[1, 2], [[:a, 1, 2], [:b, 2, 1]]],
      [[1, 2], [
        [:a, 1, 2], [:b, 1, 2],
        [:c, 2, 1], [:d, 2, 1]
      ]],
      [[1, 2, 3], [
        [:a, 1, 2], [:b, 1, 3],
        [:c, 2, 1], [:d, 2, 3],
        [:e, 3, 1], [:f, 3, 2]
      ]],
      [[1, 2, 3], [
        [:a, 1, 2], [:b, 1, 3],
        [:c, 2, 1], [:d, 2, 3],
        [:e, 3, 1], [:f, 3, 2],
        [:g, 1, 1], [:h, 3, 3]
      ]]
    ]

    cases.each do |nodes, edges|
      graph = DirectedEdgeGraph.new(nodes, edges)
      edges.group_by {|_, source, _| source }.each do |source, source_edges|
        source_edges.each do |edge|
          expected = enumerate_eulerian_circuits(edges, source, edge.first).size
          actual = graph.directed_eulerian_circuit_count(source, edge.first)
          assert_equal(expected, actual,
                       [edges, source, edge.first].inspect)
        end
      end
    end
  end

  def test_directed_eulerian_circuit_count_empty_graphs
    assert_equal(0, DirectedEdgeGraph.new([], []).directed_eulerian_circuit_count)
    assert_equal(1, DirectedEdgeGraph.new([1], []).directed_eulerian_circuit_count(1))
    assert_equal(1, DirectedEdgeGraph.new([1], []).directed_eulerian_circuit_count)
    assert_equal(0, DirectedEdgeGraph.new([1, 2], []).directed_eulerian_circuit_count(1))
  end

  def test_directed_eulerian_circuit_count_invalid_graphs
    assert_equal(0, DirectedEdgeGraph.new([1, 2], [
      [:a, 1, 2], [:b, 2, 2]
    ]).directed_eulerian_circuit_count(1, :a))

    assert_equal(0, DirectedEdgeGraph.new([1, 2, 3], [
      [:a, 1, 2], [:b, 2, 1],
      [:c, 3, 3]
    ]).directed_eulerian_circuit_count(1, :a))

    assert_equal(0, DirectedEdgeGraph.new([1, 2], [
      [:a, 1, 2], [:b, 1, 2],
      [:c, 2, 1]
    ]).directed_eulerian_circuit_count(1, :a))
  end

  def test_directed_eulerian_circuit_count_large_integer
    edge_id = 0
    edges = Array.new(10) {|node|
      destination = (node + 1) % 10
      20.times.map {
        current_edge = edge_id
        edge_id += 1
        [current_edge, node, destination]
      }
    }.flatten(1)
    graph = DirectedEdgeGraph.new((0...10).to_a, edges)
    count = graph.directed_eulerian_circuit_count(0, 0)
    factorial_19 = (1..19).inject(:*)
    expected = 20 ** 9 * factorial_19 ** 10

    assert_equal(expected, count)
    assert_kind_of(Integer, count)
  end

  def test_directed_eulerian_circuit_count_arguments
    graph = DirectedEdgeGraph.new([1, 2], [[:a, 1, 2], [:b, 2, 1]])

    assert_raise(ArgumentError) {
      graph.directed_eulerian_circuit_count(3, :a)
    }
    assert_raise(ArgumentError) {
      graph.directed_eulerian_circuit_count(1, :b)
    }
    assert_raise(ArgumentError) {
      graph.directed_eulerian_circuit_count(1, :missing)
    }
    assert_raise(NotImplementedError) {
      Object.new.extend(TSort).directed_eulerian_circuit_count(1, :a)
    }
  end

  def test_s_directed_eulerian_circuit_count_and_nil_ids
    graph = {nil => [[nil, false]], false => [[0, nil]]}
    each_node = lambda {|&block| graph.each_key(&block) }
    each_edge = lambda {|node, &block| graph.fetch(node, []).each(&block) }

    assert_equal(1, TSort.directed_eulerian_circuit_count(
      each_node, each_edge, nil, nil
    ))
  end

  def test_directed_eulerian_circuit_count_malformed_edges
    duplicate_nodes = [1, 2]
    duplicate_edges = [
      [:a, 1, 2], [:b, 2, 1], [:a, 2, 1]
    ]
    duplicate_graph = DirectedEdgeGraph.new(duplicate_nodes, duplicate_edges)

    assert_raise(ArgumentError) {
      duplicate_graph.directed_eulerian_circuit_count(1, :a)
    }

    unknown_graph = DirectedEdgeGraph.new([1, 2], [[:a, 1, 3]])
    assert_raise(ArgumentError) {
      unknown_graph.directed_eulerian_circuit_count(1, :a)
    }
  end

  private

  def enumerate_eulerian_circuits(edges, start, first_edge)
    adjacency = Hash.new {|hash, node| hash[node] = []}
    edges.each {|edge_id, source, destination|
      adjacency[source] << [edge_id, destination]
    }
    first_destination = edges.find {|edge_id, _, _|
      edge_id == first_edge
    }.last
    circuits = []

    visit = lambda do |node, used, order|
      if used == Set.new(edges.map(&:first))
        circuits << order if node == start
        return
      end

      adjacency.fetch(node, []).each do |edge_id, destination|
        next if used.include?(edge_id)
        visit.call(destination, used + [edge_id], order + [edge_id])
      end
    end

    visit.call(first_destination, Set[first_edge], [first_edge])
    circuits
  end
end
