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
  def sp_leaf(edge, source, sink)
    TSort::Decomposition.new(:edge, source, sink, edge, nil)
  end

  def sp_node(type, source, sink, children)
    TSort::Decomposition.new(type, source, sink, nil, children)
  end

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

  def test_two_terminal_series_parallel_from_decomposition_tree
    tree = sp_node(:parallel, :s, :t, [
      sp_node(:series, :s, :t, [
        sp_leaf(:a, :s, :x),
        sp_leaf(:b, :x, :t)
      ]),
      sp_node(:series, :s, :t, [
        sp_leaf(:c, :s, :y),
        sp_leaf(:d, :y, :t)
      ]),
      sp_node(:series, :s, :t, [
        sp_leaf(:e, :s, :z),
        sp_leaf(:f, :z, :t)
      ])
    ])
    graph = tree.expand
    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(true, result.ok?)
    assert_equal(:parallel, result.decomposition.type)
    assert_equal(:s, result.decomposition.source)
    assert_equal(:t, result.decomposition.sink)
    assert_equal([:a, :b, :c, :d, :e, :f],
                 result.decomposition.each_original_edge.map {|edge, _source, _sink| edge })
    assert_equal([[:a, :s, :x], [:b, :x, :t], [:c, :s, :y],
                  [:d, :y, :t], [:e, :s, :z], [:f, :z, :t]],
                 result.decomposition.each_original_edge.to_a)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_cross_edge_certificate
    graph = sp_node(:parallel, :s, :t, [
      sp_node(:series, :s, :t, [
        sp_leaf(:a, :s, :x),
        sp_leaf(:b, :x, :t)
      ]),
      sp_node(:series, :s, :t, [
        sp_leaf(:c, :s, :y),
        sp_leaf(:d, :y, :t)
      ]),
      sp_node(:series, :s, :t, [
        sp_leaf(:e, :s, :z),
        sp_leaf(:f, :z, :t)
      ])
    ]).expand
    graph.add_edge(:cross, :x, :y)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_nil(result.decomposition)
    assert_equal([:series], result.steps.map(&:first))
    assert_equal([:s, :t, :x, :y], result.residual.active_nodes)
    a_edge = result.residual.edges[:a]
    cross_edge = result.residual.edges[:cross]
    assert_equal([:s, :x], [a_edge.source, a_edge.sink])
    assert_equal([:x, :y], [cross_edge.source, cross_edge.sink])
    assert_equal(6, result.residual.edges.size)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_preserves_parallel_edge_identities
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:first, :s, :t)
    graph.add_edge(:second, :s, :t)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(true, result.ok?)
    assert_equal([:first, :second],
                 result.decomposition.children.map(&:edge))
  end

  def test_two_terminal_series_parallel_duplicate_child_occurrences
    graph = TSortHash[{:s => [:t, :t], :t => []}]
    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(true, result.ok?)
    assert_equal(2, result.decomposition.children.size)
    occurrences = result.decomposition.children.map {|child| child.edge.occurrence }
    assert_equal([0, 1], occurrences)
  end

  def test_two_terminal_series_parallel_reports_isolated_node
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:direct, :s, :t)
    graph.add_node(:isolated)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:isolated], result.diagnostics[:isolated_nodes])
    assert_equal([:s, :t, :isolated], result.residual.active_nodes)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_reports_back_edge
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:forward_one, :s, :x)
    graph.add_edge(:forward_two, :x, :t)
    graph.add_edge(:back, :t, :x)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:x, :t].sort, result.diagnostics[:cyclic_nodes].sort)
    assert_include(result.diagnostics[:cyclic_edges], :back)
    assert_equal([:s, :t, :x], result.residual.active_nodes)
    assert_equal(3, result.residual.edges.size)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_reports_off_path_component
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:terminal_edge, :s, :t)
    graph.add_edge(:off_path, :u, :v)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:u, :v], result.diagnostics[:unreachable_nodes])
    assert_equal([:u, :v], result.diagnostics[:nodes_unable_to_reach_sink])
    assert_equal([:u, :v], result.diagnostics[:nodes_not_on_source_sink_path])
    assert_equal([:off_path], result.diagnostics[:edges_not_on_source_sink_path])
    assert_include(result.residual.edges, :off_path)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_keeps_off_path_internal_node
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:terminal_edge, :s, :t)
    graph.add_edge(:off_in, :u, :w)
    graph.add_edge(:off_out, :w, :v)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:u, :w, :v], result.diagnostics[:unreachable_nodes])
    assert_equal([:s, :t, :u, :w, :v], result.residual.active_nodes)
    assert_equal([:off_in, :off_out],
                 result.residual.edges.keys - [:terminal_edge])
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_reports_self_loop
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:terminal_edge, :s, :t)
    graph.add_edge(:self_loop, :s, :s)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_include(result.diagnostics[:cyclic_nodes], :s)
    assert_include(result.diagnostics[:cyclic_edges], :self_loop)
    assert_include(result.diagnostics[:edges_entering_source], :self_loop)
    assert_include(result.residual.edges, :self_loop)
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_reports_terminal_boundary_edges
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:terminal_edge, :s, :t)
    graph.add_edge(:into_source, :x, :s)
    graph.add_edge(:out_of_sink, :t, :y)

    result = graph.two_terminal_series_parallel(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:into_source], result.diagnostics[:edges_entering_source])
    assert_equal([:out_of_sink], result.diagnostics[:edges_leaving_sink])
    assert_equal(result.residual, result.replay)
  end

  def test_two_terminal_series_parallel_validates_terminals
    graph = TSort::SeriesParallel::Graph.new(:s, :t)
    graph.add_edge(:direct, :s, :t)

    assert_raise(ArgumentError) do
      graph.two_terminal_series_parallel(:s, :missing)
    end
    assert_raise(ArgumentError) do
      graph.two_terminal_series_parallel(:s, :s)
    end
  end

  def test_s_two_terminal_series_parallel_with_explicit_edges
    edges = {
      :s => [[:first, :t], [:second, :t]],
      :t => []
    }
    each_node = lambda {|&block| edges.each_key(&block) }
    each_child = lambda do |node, &block|
      edges[node].each {|_edge, child| block.call(child) }
    end
    each_edge = lambda do |node, &block|
      edges[node].each {|edge, child| block.call(edge, child) }
    end

    result = TSort.two_terminal_series_parallel(
      each_node, each_child, :s, :t, each_edge
    )

    assert_equal(true, result.ok?)
    assert_equal([:first, :second],
                 result.decomposition.children.map(&:edge))
    assert_equal(result.residual, result.replay)
  end
end
