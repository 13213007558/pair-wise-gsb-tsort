# TSort

TSort implements topological sorting using Tarjan's algorithm for
strongly connected components.

TSort is designed to be able to be used with any object which can be
interpreted as a directed graph.

TSort requires two methods to interpret an object as a graph,
`tsort_each_node` and `tsort_each_child`.

* `tsort_each_node` is used to iterate for all nodes over a graph.
* `tsort_each_child` is used to iterate for child nodes of a given node.

The equality of nodes are defined by eql? and hash since
TSort uses Hash internally.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tsort'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install tsort

## Usage

The following example demonstrates how to mix the TSort module into an
existing class (in this case, Hash). Here, we're treating each key in
the hash as a node in the graph, and so we simply alias the required
`#tsort_each_node` method to Hash's `#each_key` method. For each key in the
hash, the associated value is an array of the node's child nodes. This
choice in turn leads to our implementation of the required `#tsort_each_child`
method, which fetches the array of child nodes and then iterates over that
array using the user-supplied block.

```ruby
require 'tsort'

class Hash
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

{1=>[2, 3], 2=>[3], 3=>[], 4=>[]}.tsort
#=> [3, 2, 1, 4]

{1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}.strongly_connected_components
#=> [[4], [2, 3], [1]]
```

## Directed Eulerian circuits

To count circuits in a directed multigraph, provide an edge iterator in
addition to the node iterator. Each edge has an independent ID, so parallel
edges are counted as distinct choices:

```ruby
require 'tsort'

class DirectedGraph
  include TSort

  def initialize(nodes, edges)
    @nodes = nodes
    @edges = Hash.new { |hash, node| hash[node] = [] }
    edges.each { |edge_id, source, destination|
      @edges[source] << [edge_id, destination]
    }
  end

  def tsort_each_node(&block)
    @nodes.each(&block)
  end

  def tsort_each_edge(node, &block)
    @edges.fetch(node, []).each(&block)
  end
end

edges = [[:a, 1, 2], [:b, 2, 1]]
graph = DirectedGraph.new([1, 2], edges)

# Fixed start 1 and fixed first edge :a.
graph.directed_eulerian_circuit_count(1, :a) #=> 1
```

For an Eulerian graph with `m` edges, let `c` be the returned count.

* Fixed start, any first edge: `outdegree(start) * c`.
* Cyclic circuits, with rotations identified: `c`.
* Linear edge sequences without a fixed start or first edge: `m * c`.

An empty graph with no vertices returns `0`. One isolated vertex with no
edges returns `1` for the trivial empty circuit. A zero-edge graph with more
than one vertex returns `0`.

The method checks balanced in/out degrees and strong connectivity among
edge-bearing vertices, then uses the directed matrix-tree theorem and BEST
theorem. It returns a large `Integer` without enumerating all circuits.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/tsort.
