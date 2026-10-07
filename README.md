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

## Two-terminal series-parallel graphs

`#two_terminal_series_parallel(source, sink)` recognizes a directed
two-terminal series-parallel graph. Success returns a decomposition tree. The
tree keeps the original edge identities in its leaves and can rebuild the graph.

```ruby
g = TSort::SeriesParallel::Graph.new(:s, :t)
g.add_edge(:a, :s, :x)
g.add_edge(:b, :x, :t)
g.add_edge(:c, :s, :y)
g.add_edge(:d, :y, :t)

result = g.two_terminal_series_parallel(:s, :t)
result.ok?                 #=> true
result.decomposition.type  #=> :parallel
result.decomposition.expand
```

Failure is also represented by a certificate. `residual` is the graph after
all valid series and parallel reductions on source-to-sink paths, and `steps`
rebuilds that residual graph. `diagnostics` lists isolated nodes, cyclic/back
edges, terminal-boundary edges, and nodes or edges outside source-to-sink
paths.

```ruby
g.add_edge(:cross, :x, :y)
result = g.two_terminal_series_parallel(:s, :t)
result.ok?                  #=> false
result.residual.edges.keys
result.replay == result.residual
```

Repeated children are treated as distinct parallel edges. A graph adapter can
instead implement `tsort_each_edge(node)` and yield `(edge, child)` pairs to
provide explicit edge identities. The class-method form accepts `each_node`,
`each_child`, and an optional `each_edge` callable.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/tsort.
