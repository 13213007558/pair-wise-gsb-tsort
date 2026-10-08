# frozen_string_literal: true

module TSort
  # TSort::Reliability computes two-terminal network reliability: the
  # probability that a +source+ node can still reach a +sink+ node when
  # every directed edge of the graph survives independently with its own
  # probability.
  #
  #   require 'tsort'
  #
  #   edges = [[:s, :a], [:s, :b], [:a, :x], [:b, :x], [:x, :t]]
  #   rel = TSort::Reliability.new(edges)
  #
  #   # Numeric, one survival probability per edge:
  #   rel.probability(:s, :t, [0.9, 0.9, 0.9, 0.9, 0.99])
  #
  #   # Exact integer-coefficient polynomial in a shared variable p:
  #   rel.polynomial(:s, :t)   #=> [0, 0, 0, 2, 0, -1]  (2*p**3 - p**5)
  #
  #   # Number of decision-diagram states used for the computation:
  #   rel.state_count(:s, :t)
  #
  # Edges are independent; paths are not.  Two routes sharing a single
  # bridge edge are handled correctly because the computation is a
  # frontier-based decision diagram over edge variables with shared
  # (memoized) states, never a mechanical enumeration of the 2**E
  # subgraphs and never a path-based expansion.
  #
  # Parallel edges between the same ordered pair of nodes are merged
  # into a single equivalent edge (survival probability
  # 1 - (1-p1)*(1-p2)*...) before the diagram is built, and self-loops
  # are dropped, since neither affects reachability.
  class Reliability
    # The original list of directed edges, as +[u, v]+ pairs.
    attr_reader :edges

    # +edges+ is an enumerable of +[u, v]+ directed pairs.  Parallel
    # edges are allowed and merged; self-loops are ignored.
    def initialize(edges)
      @edges = edges.map { |edge| u, v = edge; [u, v] }
      @node_index = {}
      @edges.each do |u, v|
        @node_index[u] = @node_index.size unless @node_index.key?(u)
        @node_index[v] = @node_index.size unless @node_index.key?(v)
      end
      # Groups of parallel edges: [u_id, v_id, [original edge indexes]].
      @groups = []
      group_index = {}
      @edges.each_with_index do |(u, v), i|
        next if u == v
        key = [u, v]
        group = group_index[key]
        unless group
          group = [@node_index[u], @node_index[v], []]
          group_index[key] = group
          @groups << group
        end
        group[2] << i
      end
      @diagrams = {}
    end

    # The probability that +source+ can reach +sink+ when each original
    # edge survives independently with the probability given at the
    # same position in +probabilities+.
    def probability(source, sink, probabilities)
      unless probabilities.size == @edges.size
        raise ArgumentError,
          "expected #{@edges.size} probabilities, got #{probabilities.size}"
      end
      return 1 if source == sink
      diagram = diagram_for(source, sink)
      return 0 unless diagram
      probs = @groups.map do |_, _, indexes|
        1 - indexes.inject(1) { |acc, i| acc * (1 - probabilities[i]) }
      end
      diagram.eval_numeric(probs)
    end

    # The reliability as an exact polynomial in a single variable +p+
    # shared by every edge.  Returns an array of Integer coefficients,
    # lowest degree first: coefficient at index +k+ multiplies +p**k+.
    def polynomial(source, sink)
      return [1] if source == sink
      diagram = diagram_for(source, sink)
      return [0] unless diagram
      polys = @groups.map { |_, _, indexes| self.class.one_minus_one_minus_p(indexes.size) }
      diagram.eval_polynomial(polys)
    end

    # The number of non-terminal states of the decision diagram built
    # for the +source+/+sink+ pair.  Useful to confirm the computation
    # shares states instead of enumerating 2**E subgraphs.
    def state_count(source, sink)
      return 0 if source == sink
      diagram = diagram_for(source, sink)
      diagram ? diagram.state_count : 0
    end

    # Evaluates a polynomial given as integer coefficients (lowest
    # degree first) at +p+.
    def self.evaluate_polynomial(coeffs, p)
      coeffs.reverse.inject(0) { |acc, c| acc * p + c }
    end

    # Polynomial addition; coefficients are arrays, lowest degree first.
    def self.poly_add(a, b)
      n = [a.size, b.size].max
      Array.new(n) { |i| (a[i] || 0) + (b[i] || 0) }
    end

    # Polynomial subtraction; coefficients are arrays, lowest degree first.
    def self.poly_sub(a, b)
      n = [a.size, b.size].max
      Array.new(n) { |i| (a[i] || 0) - (b[i] || 0) }
    end

    # Polynomial multiplication; coefficients are arrays, lowest degree first.
    def self.poly_mul(a, b)
      return [0] if a.empty? || b.empty?
      result = Array.new(a.size + b.size - 1, 0)
      a.each_with_index do |ai, i|
        b.each_with_index do |bj, j|
          result[i + j] += ai * bj
        end
      end
      result
    end

    # Strips trailing zero coefficients, keeping at least one.
    def self.poly_normalize(coeffs)
      coeffs = coeffs.dup
      coeffs.pop while coeffs.size > 1 && coeffs.last == 0
      coeffs
    end

    # 1 - (1-p)**k as integer coefficients: the survival polynomial of
    # k merged parallel edges each surviving with probability p.
    def self.one_minus_one_minus_p(k)
      pow = [1]
      k.times { pow = poly_mul(pow, [1, -1]) }
      poly_normalize(poly_sub([1], pow))
    end

    private

    def diagram_for(source, sink)
      s = @node_index[source]
      t = @node_index[sink]
      return nil unless s && t
      @diagrams[[s, t]] ||=
        Diagram.new(@groups.map { |u, v, _| [u, v] }, s, t)
    end

    # A frontier-based binary decision diagram over edge variables.
    #
    # Edges are decided in a fixed order.  A state is the reachability
    # relation among the frontier nodes (the sink, plus the nodes still
    # touched by undecided edges) induced by the surviving decided
    # edges, plus the set of frontier nodes reachable from the source.
    # The sink always stays in the frontier so that "this frontier node
    # can already reach the sink" is never forgotten.  Identical
    # states are shared through memoization, and identical
    # (variable, low, high) nodes through a unique table, so the number
    # of states stays far below 2**E.
    #
    # Note that the simpler "contract the edge" factoring used for
    # undirected graphs is invalid for directed graphs (contracting a
    # surviving edge u->v would wrongly allow paths to travel v->u);
    # the frontier relation avoids that pitfall.
    class Diagram # :nodoc:
      FALSE_ID = 0
      TRUE_ID = 1

      attr_reader :state_count

      def initialize(edges, source, sink)
        @edges = edges
        @sink = sink
        m = edges.size
        @frontier = Array.new(m + 1)
        frontier = [sink]
        (m - 1).downto(0) do |i|
          u, v = edges[i]
          frontier = (frontier | [u, v]).sort
          @frontier[i] = frontier
        end
        @frontier[m] = [].freeze
        @nodes = []   # node id - 2 => [edge index, low id, high id]
        @unique = {}  # [edge index, low id, high id] => node id
        @memo = {}    # state key => node id
        initial_reach = {}
        @frontier[0].each { |x| initial_reach[x] = [x].freeze }
        @root = expand(0, initial_reach, [source].freeze)
        @state_count = @nodes.size
      end

      def eval_numeric(probs)
        values = [0, 1]
        @nodes.each do |i, low, high|
          p = probs[i]
          values << p * values[high] + (1 - p) * values[low]
        end
        values[@root]
      end

      def eval_polynomial(polys)
        values = [[0], [1]]
        @nodes.each do |i, low, high|
          q = polys[i]
          values << Reliability.poly_add(
            Reliability.poly_mul(q, values[high]),
            Reliability.poly_mul(Reliability.poly_sub([1], q), values[low]))
        end
        Reliability.poly_normalize(values[@root])
      end

      private

      # reach: Hash{frontier node => sorted Array of frontier nodes
      # reachable from it through surviving decided edges} (reflexive,
      # transitively closed).  from_s: sorted Array of frontier nodes
      # reachable from the source.
      def expand(i, reach, from_s)
        return TRUE_ID if from_s.include?(@sink)
        return FALSE_ID if i == @edges.size
        return FALSE_ID unless can_still_reach?(i, reach, from_s)
        key = [i, reach.sort, from_s]
        cached = @memo[key]
        return cached if cached

        u, v = @edges[i]
        low = expand(i + 1, restrict_reach(reach, i + 1),
                     restrict_set(from_s, i + 1))
        high_reach, high_from_s, sink_hit = add_edge(reach, from_s, u, v, i)
        high = sink_hit ? TRUE_ID : expand(i + 1, high_reach, high_from_s)

        result =
          if low == high
            low
          else
            node = [i, low, high]
            @unique[node] ||= begin
              @nodes << node
              @nodes.size + 1
            end
          end
        @memo[key] = result
      end

      def restrict_reach(reach, i)
        frontier = @frontier[i]
        restricted = {}
        frontier.each { |x| restricted[x] = reach[x] & frontier }
        restricted
      end

      def restrict_set(from_s, i)
        from_s & @frontier[i]
      end

      # Returns the state after deciding that edge u->v survives:
      # [new reach relation, new from_s, whether the sink became
      # reachable from the source].
      def add_edge(reach, from_s, u, v, i)
        adj = {}
        @frontier[i].each { |x| adj[x] = reach[x].dup }
        adj[u] << v
        next_frontier = @frontier[i + 1]
        new_reach = {}
        next_frontier.each do |x|
          new_reach[x] = bfs(adj, [x]) & next_frontier
        end
        reachable = bfs(adj, from_s)
        [new_reach, reachable & next_frontier, reachable.include?(@sink)]
      end

      # Pruning reduction: if the sink is unreachable even with every
      # remaining edge present, this state is a failure.
      def can_still_reach?(i, reach, from_s)
        adj = {}
        reach.each { |x, ys| adj[x] = ys.dup }
        (i...@edges.size).each do |j|
          u, v = @edges[j]
          (adj[u] ||= []) << v
        end
        bfs(adj, from_s).include?(@sink)
      end

      def bfs(adj, starts)
        seen = {}
        stack = starts.dup
        starts.each { |x| seen[x] = true }
        until stack.empty?
          x = stack.pop
          next unless (ys = adj[x])
          ys.each do |y|
            unless seen[y]
              seen[y] = true
              stack << y
            end
          end
        end
        seen.keys.sort
      end
    end
  end
end
