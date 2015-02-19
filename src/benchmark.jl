abstract Problem ## A computational problem
abstract Algorithm # An algorithm is a procedure to solve it
typealias Capture Union(Symbol, (Symbol, Symbol))
# We shall call a pair of them a run
typealias Run (Algorithm, Problem)

# global mutable directory connecting benchmark names with dataframes
clear_benchmarks!() = global benchmarks = Dict{Capture, Vector{Any}}()
clear_benchmarks!()

function capturebench(capture::Symbol, data)
  global benchmarks
  if haskey(benchmarks,capture)
    push!(benchmarks[capture], data)
  else
    benchmarks[capture] = [data]
  end
end

function capturebench(capture::(Symbol,Symbol), data)
  global benchmarks
  joined_capture = symbol("$(capture[1])_$(capture[2])")
  if haskey(benchmarks,joined_capture)
    push!(benchmarks[joined_capture], data[capture[2]])
  else
    benchmarks[joined_capture] = [data[capture[2]]]
  end
end

function register_benchmark!(c::Symbol)
  fl = Filter(gensym("benchmark"), data->capturebench(c,data), true, false)
  register!(c, fl)
  fl
end

function register_benchmark!(c::(Symbol,Symbol))
  fl = Filter(gensym("benchmark"), data->capturebench(c,data), true, true)
  register!(c[1], fl)
  fl
end

# Creates a filter for each capture and registers to
# The associated data to be captured
function register_benchmarks!{C<:Capture}(captures::Vector{C})
  fls = Array(Filter, length(captures))
  for i = 1:length(captures)
    let capture = captures[i]
      fls[i] = register_benchmark!(capture)
    end
  end
  fls
end

function disable_benchmarks!{C<:Capture}(captures::Vector{C})
  for capture in captures
    isa(capture,Symbol) && disable_filter!(capture,:benchmark)
    isa(capture,(Symbol,Symbol)) && disable_filter!(capture[1],:benchmark)
  end
end

# Register lenses
function setup!{C<:Capture}(captures::Vector{C})
  clear_benchmarks!()
  register_benchmarks!(captures)
end

# Unregister lenses and delete benchmark data
function cleanup!(fls::Vector{Filter})
  captures = [fl.name for fl in fls]
  for capture in captures delete_filter!(capture) end
  clear_benchmarks!()
end

## Run Benchmarks
## ==============

# Do a quick and dirty bechmark, captures captures and returns result too
function quickbench{C<:Capture}(f::Function, captures::Vector{C})
  fls = setup!(captures)
  value, Δt, Δb = @timed(f())
  lens(:total_time, Δt)
  res = deepcopy(benchmarks)
  cleanup!(fls)
  value,res
end

# Hack for failture of type inference to detect [:a, (:a,b)] as Capture vec
quickbench(f::Function, captures::Vector{Any}) = quickbench(f,Capture[captures...])

# macro quickbench(e)
#   @q
#   setup!()
#   e
#   cleanup()!
# end

# Run all the benchmarks
# function runbenchmarks(torun::Vector{Algorithm, Benchmark})
#   e
# end

# Run all the benchmarks with all the algorithms
function runbenchmarks{A<:Algorithm, B<:Problem}(algos::Vector{A},
                                                   benches::Vector{B};
                                                   newseed = false,
                                                   runname::String = "")
  results = Dict{(Algorithm, Benchmark),Any}()
  runiter = 1; nruns = length(benches) * length(algos)
  nfailures = 0

  thisrundir = joinpath(benchdir, "data", "$(runname)-$(string(Dates.now()))")
  mkdir(thisrundir)

  for j = 1:length(benches), i = 1:length(algos)
    println("\nRUNNING $runiter of $nruns, $nfailures so far")
    print("$(algos[i]) \n")
    print("$(benches[j]) \n")
    newseed && srand(345678) # Set Random Seed
    restart_counter!()
    try
      results[(algos[i],benches[j])] = benchmark(algos[i], benches[j])
      dumpbenchmark(thisrundir,results)
    catch er
      nfailures += 1
      @show er
      @show j
      @show length(benches)
      results[(algos[i],benches[j])] = er
    end
    runiter += 1
  end
  println("$nfailures failures")
  dumpbenchmark(thisrundir,results,"all")
  results
end

function dumpbenchmark(thisrundir,x,suffix::String = "")
  fname = "$(string(Dates.now()))-$suffix"
  path = joinpath(thisrundir, fname)
  f = open(path,"w")
  serialize(f,x)
  close(f)
end