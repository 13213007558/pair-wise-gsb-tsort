# frozen_string_literal: true

require 'tsort'
require 'test/unit'

class UpdatableTopoViewTest < Test::Unit::TestCase # :nodoc:
  def test_initial_order_is_kept
    view = TSort::UpdatableTopoView.new([:a, :b, :c])
    assert_equal([:a, :b, :c], view.order)
    assert_equal(3, view.size)
    assert_equal([], view.edges)
    assert_equal(true, view.include?(:a))
    assert_equal(false, view.include?(:z))
  end

  def test_duplicate_initial_nodes_rejected
    assert_raise(ArgumentError) { TSort::UpdatableTopoView.new([1, 2, 1]) }
  end

  def test_add_node_appends
    view = TSort::UpdatableTopoView.new([:a])
    assert_equal(true, view.add_node(:b))
    assert_equal(false, view.add_node(:b))
    assert_equal([:a, :b], view.order)
  end

  def test_add_edge_without_reorder
    view = TSort::UpdatableTopoView.new([:a, :b, :c, :d])
    assert_equal(true, view.add_edge(:a, :c))
    assert_equal([:a, :b, :c, :d], view.order)
    assert_equal([[:a, :c]], view.edges)
    assert_equal([:a, :c], view.last_inspected)
  end

  def test_add_edge_with_unknown_nodes
    view = TSort::UpdatableTopoView.new([:a])
    assert_equal(true, view.add_edge(:x, :y))
    assert_equal([:a, :x, :y], view.order)
    assert_equal(true, view.add_edge(:a, :x))
    assert_equal([:a, :x, :y], view.order)
  end

  def test_add_edge_reorders_only_affected_region
    view = TSort::UpdatableTopoView.new([:a, :b, :c, :d])
    assert_equal(true, view.add_edge(:c, :a))
    assert_equal([:c, :b, :a, :d], view.order)
    assert_equal([:a, :c], view.last_inspected.sort)
  end

  def test_local_update_does_not_scan_whole_graph
    # two parallel chains: 0 -> 1 -> 2 -> 3 and 4 -> 5
    view = TSort::UpdatableTopoView.new([0, 1, 2, 3, 4, 5])
    view.add_edge(0, 1)
    view.add_edge(1, 2)
    view.add_edge(2, 3)
    view.add_edge(4, 5)
    assert_equal(true, view.add_edge(5, 1))
    # B = {4, 5} moves in front of F = {1, 2, 3}; node 0 is untouched
    # and was never inspected.
    assert_equal([0, 4, 5, 1, 2, 3], view.order)
    assert_equal([1, 2, 3, 4, 5], view.last_inspected.sort)
    assert_equal(false, view.last_inspected.include?(0))
  end

  def test_cycle_returns_path_and_keeps_view
    view = TSort::UpdatableTopoView.new([1, 2, 3])
    view.add_edge(1, 2)
    view.add_edge(2, 3)
    before = view.order
    path = view.add_edge(3, 1)
    assert_equal([3, 1, 2, 3], path)
    assert_equal(before, view.order)
    assert_equal([[1, 2], [2, 3]], view.edges)
    # the view is still usable afterwards
    assert_equal(true, view.add_edge(1, 3))
    assert_equal(true, view.remove_edge(2, 3))
    assert_equal([1, 2, 3], view.order)
  end

  def test_self_loop
    view = TSort::UpdatableTopoView.new([1, 2])
    assert_equal([1, 1], view.add_edge(1, 1))
    assert_equal([], view.edges)
    assert_equal([1, 2], view.order)
  end

  def test_remove_edge_preserves_order
    view = TSort::UpdatableTopoView.new([:a, :b, :c, :d])
    view.add_edge(:a, :b)
    view.add_edge(:c, :d)
    assert_equal(true, view.remove_edge(:a, :b))
    assert_equal([:a, :b, :c, :d], view.order)
    assert_equal([[:c, :d]], view.edges)
    assert_equal(false, view.remove_edge(:a, :b))
    assert_equal([:a, :b], view.last_inspected)
  end

  def test_remove_node_preserves_relative_order
    view = TSort::UpdatableTopoView.new([:a, :b, :c, :d, :e])
    view.add_edge(:a, :c)
    view.add_edge(:c, :e)
    assert_equal(true, view.remove_node(:c))
    assert_equal([:a, :b, :d, :e], view.order)
    assert_equal([], view.edges)
    assert_equal([:a, :c, :e], view.last_inspected.sort)
    assert_equal(false, view.remove_node(:c))
    assert_equal(false, view.include?(:c))
    assert_equal(4, view.size)
  end

  # Random small graphs: after every update the view's ordering is
  # checked for legality against a from-scratch TSort recomputation of
  # the mirrored graph, and the stability guarantees are verified pair
  # by pair.
  def test_random_updates_against_from_scratch
    10.times do |trial|
      rng = Random.new(trial * 7919 + 42)
      alive = (0...6).to_a.shuffle(random: rng)
      view = TSort::UpdatableTopoView.new(alive)
      succ = Hash.new {|h, k| h[k] = [] }
      prev_order = view.order
      80.times do
        op = rng.rand(4)
        if op <= 1 || alive.size < 2
          u = alive[rng.rand(alive.size)]
          v = alive[rng.rand(alive.size)]
          result = view.add_edge(u, v)
          if result == true
            succ[u] << v unless u == v || succ[u].include?(v)
            assert_valid_order(view, alive, succ)
            assert_no_uninspected_swaps(view, prev_order)
          else
            assert_cycle_path(result, u, v, succ)
            assert_equal(prev_order, view.order)
          end
        elsif op == 2
          u = alive[rng.rand(alive.size)]
          v = alive[rng.rand(alive.size)]
          expected = u != v && succ[u].include?(v)
          assert_equal(expected, view.remove_edge(u, v))
          succ[u].delete(v)
          assert_equal(prev_order, view.order)
        else
          x = alive[rng.rand(alive.size)]
          assert_equal(true, view.remove_node(x))
          alive.delete(x)
          succ.delete(x)
          succ.each_value {|ws| ws.delete(x) }
          assert_equal(prev_order - [x], view.order)
        end
        assert_equal(mirror_edges(succ, alive), view.edges.sort)
        prev_order = view.order
      end
    end
  end

  private

  def mirror_edges(succ, alive)
    succ.flat_map {|u, ws|
      ws.select {|v| alive.include?(u) && alive.include?(v) }.map {|v| [u, v] }
    }.sort
  end

  def assert_valid_order(view, alive, succ)
    order = view.order
    assert_equal(alive.sort, order.sort)
    pos = {}
    order.each_with_index {|x, i| pos[x] = i }
    succ.each do |u, ws|
      ws.each do |v|
        next unless pos.key?(u) && pos.key?(v)
        assert(pos[u] < pos[v], "edge #{u}->#{v} violated in #{order.inspect}")
      end
    end
    # from-scratch cross-check: the mirrored graph must be acyclic, so a
    # full TSort recomputation must succeed.
    each_node = lambda {|&b| alive.each(&b) }
    each_child = lambda {|n, &b| succ[n].each(&b) }
    TSort.tsort(each_node, each_child)
  end

  # Stability: a pair of surviving nodes may only be inverted if the
  # update inspected at least one of them (the F and B sets of
  # add_edge); two uninspected nodes never change their relative order.
  def assert_no_uninspected_swaps(view, prev_order)
    inspected = view.last_inspected
    now = view.order
    prev_pos = {}
    prev_order.each_with_index {|x, i| prev_pos[x] = i }
    now_pos = {}
    now.each_with_index {|x, i| now_pos[x] = i }
    common = prev_order & now
    common.each do |x|
      common.each do |y|
        next if x == y
        next unless prev_pos[x] < prev_pos[y] && now_pos[x] > now_pos[y]
        assert(inspected.include?(x) || inspected.include?(y),
               "pair #{x.inspect},#{y.inspect} swapped without inspection")
      end
    end
  end

  def assert_cycle_path(path, u, v, succ)
    assert_kind_of(Array, path)
    assert_equal(u, path.first)
    assert_equal(u, path.last)
    assert_equal(v, path[1])
    (1...path.size - 1).each do |i|
      assert(succ[path[i]].include?(path[i + 1]),
             "#{path.inspect} step #{path[i]}->#{path[i + 1]} is not an edge")
    end
  end
end
