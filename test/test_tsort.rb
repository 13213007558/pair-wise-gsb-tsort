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

class ReferenceGraph < Hash # :nodoc:
  include TSort
  alias tsort_each_node each_key
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

  def test_self_loop
    h = TSortHash[{1=>[1]}]
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

  def test_topological_view_initializes_and_materializes
    view = TSort::TopologicalView.new([3, 2, 1, 4],
                                      1 => [2, 3], 2 => [3])

    assert_equal([3, 2, 1, 4], view.to_a)
    assert_equal(4, view.size)
    assert(view.edge?(1, 2))
    assert(!view.edge?(2, 1))
    assert_equal([3, 2, 1, 4], view.tsort)
  end

  def test_topological_view_rejects_invalid_initial_order_or_nodes
    assert_raise(ArgumentError) do
      TSort::TopologicalView.new([1, 2, 3], 1 => [2])
    end
    assert_raise(ArgumentError) do
      TSort::TopologicalView.new([1, 1], 1 => [])
    end
    assert_raise(ArgumentError) do
      TSort::TopologicalView.new([1], 1 => [2])
    end
    assert_raise(ArgumentError) do
      TSort::TopologicalView.new([1], 1 => [1])
    end
  end

  def test_topological_view_add_satisfied_edge_does_not_reorder
    view = TSort::TopologicalView.new([3, 2, 1, 4], 1 => [2])

    result = view.add_edge(4, 1)

    assert(result.success?)
    assert(result.added)
    assert(!result.reordered)
    assert_equal([], result.span_nodes)
    assert_equal([4], result.checked_nodes)
    assert_equal([3, 2, 1, 4], view.to_a)
    assert_equal(result, view.last_result)
  end

  def test_topological_view_add_edge_is_locally_stable
    view = TSort::TopologicalView.new((0..7).to_a)

    result = view.add_edge(2, 6)

    assert(result.success?)
    assert(result.reordered)
    assert_equal([2, 3, 4, 5, 6], result.span_nodes)
    assert_equal([2, 3, 4, 5, 6], result.checked_nodes)
    assert_equal([3, 4, 5, 6, 2], view.to_a[2, 5])
    assert_equal([0, 1, 7], view.to_a.values_at(0, 1, -1))
    assert_topologically_valid(view)
  end

  def test_topological_view_keeps_earliest_unrelated_old_positions
    view = TSort::TopologicalView.new([0, 1, 2, 3, 4])

    view.add_edge(0, 4)

    assert_equal([1, 2, 3, 4, 0], view.to_a)
  end

  def test_topological_view_rejects_cycle_and_keeps_view
    view = TSort::TopologicalView.new([3, 2, 1], 1 => [2], 2 => [3])
    before = view.to_a

    result = view.add_edge(3, 1)

    assert(result.cyclic?)
    assert(!result.success?)
    assert_equal([3, 1, 2, 3], result.cycle_path)
    assert_cycle_path(view, result.cycle_path, 3, 1)
    assert_equal(before, view.to_a)
    assert(!view.edge?(3, 1))
    assert(view.edge?(1, 2))

    result = view.add_edge(1, 1)
    assert(result.cyclic?)
    assert_equal([1, 1], result.cycle_path)
    assert_equal(before, view.to_a)
  end

  def test_topological_view_satisfied_edge_needs_no_search
    view = TSort::TopologicalView.new([3, 2, 1, 4],
                                      1 => [2], 2 => [3])

    result = view.add_edge(4, 3)

    assert(result.success?)
    assert(!result.reordered)
    assert(view.edge?(4, 3))
    assert_equal([4], result.checked_nodes)
    assert_equal([3, 2, 1, 4], view.to_a)
  end

  def test_topological_view_delete_edge_does_not_reorder
    order = [3, 2, 1, 4]
    view = TSort::TopologicalView.new(order, 1 => [2, 3], 2 => [3])

    result = view.delete_edge(1, 2)

    assert(result.removed)
    assert(!result.reordered)
    assert(!view.edge?(1, 2))
    assert(view.edge?(1, 3))
    assert_equal(order, view.to_a)
    assert_equal([1, 2], result.checked_nodes)

    missing = view.delete_edge(1, 2)
    assert(!missing.removed)
  end

  def test_topological_view_delete_node_preserves_survivor_order
    view = TSort::TopologicalView.new([3, 2, 1, 4],
                                      1 => [2, 3], 2 => [3])

    result = view.delete_node(2)

    assert(result.removed)
    assert_equal([2, 1, 3], result.checked_nodes)
    assert_equal([3, 1, 4], view.to_a)
    assert(!view.include?(2))
    assert(!view.edge?(1, 2))
    assert(view.edge?(1, 3))
    assert_topologically_valid(view)
  end

  def test_topological_view_random_additions_match_full_tsort
    nodes = (0...8).to_a
    pairs = nodes.product(nodes).reject { |parent, child| parent == child }

    20.times do |seed|
      view = TSort::TopologicalView.new(nodes)
      reference = empty_reference_graph(nodes)
      random = Random.new(7440 + seed)

      60.times do
        parent, child = pairs.sample(random: random)
        result = view.add_edge(parent, child)

        if result.cyclic?
          assert(!acyclic_reference?(reference.merge(parent => reference[parent] + [child])),
                 "seed=#{seed} rejected an acyclic edge #{parent}->#{child}")
          assert_cycle_path(view, result.cycle_path, parent, child)
          assert_local_check(result, view)
        else
          reference[parent] << child unless reference[parent].include?(child)
          assert(acyclic_reference?(reference),
                 "seed=#{seed} accepted a cyclic edge #{parent}->#{child}")
          assert_topologically_valid(view)
          assert_local_check(result, view)

          unless result.span_nodes.empty?
            span_set = result.span_nodes
            result.checked_nodes.each do |node|
              assert(nodes.include?(node))
              assert(span_set.include?(node))
            end
          end
        end
      end
    end
  end

  def test_topological_view_random_deletions_preserve_order
    nodes = (0...8).to_a
    10.times do |seed|
      view = TSort::TopologicalView.new(nodes)
      reference = empty_reference_graph(nodes)
      random = Random.new(8440 + seed)

      12.times do
        parent = nodes.sample(random: random)
        child = nodes.sample(random: random)
        next if parent >= child
        view.add_edge(parent, child)
      end
      view.each { |parent| reference[parent] = view.tsort_each_child(parent).to_a }
      assert_topologically_valid(view)

      20.times do
        before = view.to_a
        break if before.empty?
        if random.rand(3).zero?
          node = before.sample(random: random)
          result = view.delete_node(node)
          incident = result.affected_nodes - [node]
          reference.delete(node)
          reference.each_value { |children| children.delete(node) }

          assert_equal(before - [node], view.to_a)
          assert_equal([node, *incident].sort, result.checked_nodes.sort)
        else
          existing_edges = reference.flat_map do |parent, children|
            children.map { |child| [parent, child] }
          end
          if existing_edges.empty?
            assert_topologically_valid(view)
            next
          end

          parent, child = existing_edges.sample(random: random)
          result = view.delete_edge(parent, child)
          reference[parent].delete(child)

          assert_equal(before, view.to_a)
          assert_equal([parent, child].sort, result.checked_nodes.sort)
        end
        assert_topologically_valid(view)
        assert(acyclic_reference?(reference))
      end
    end
  end

  private

  def empty_reference_graph(nodes)
    ReferenceGraph[nodes.map { |node| [node, []] }]
  end

  def acyclic_reference?(graph)
    graph.tsort
    true
  rescue TSort::Cyclic
    false
  end

  def assert_topologically_valid(view)
    order = view.to_a
    position = {}
    order.each_with_index { |node, index| position[node] = index }
    order.each do |parent|
      view.tsort_each_child(parent) do |child|
        assert(position[child] < position[parent],
               "invalid order #{order.inspect} for edge #{parent}->#{child}")
      end
    end
    assert_equal(view.tsort, order)
  end

  def assert_cycle_path(view, path, parent, child)
    assert_equal(parent, path.first)
    assert_equal(parent, path.last)
    assert_equal(parent, path[0])
    assert_equal(child, path[1])
    path.each_cons(2) do |source, destination|
      next if source == parent && destination == child
      assert(view.edge?(source, destination),
             "missing existing edge in cycle path #{path.inspect}")
    end
  end

  def assert_local_check(result, view)
    assert(result.checked_nodes.all? { |node| view.include?(node) })
    if result.span_nodes.empty?
      if result.cyclic?
        assert_equal(result.searched_nodes.sort, result.checked_nodes.sort)
      else
        assert(result.checked_nodes.length <= 1)
      end
    else
      span_set = result.span_nodes
      result.searched_nodes.each do |node|
        assert(span_set.include?(node) || node == result.affected_nodes.first)
      end
    end
  end
end
