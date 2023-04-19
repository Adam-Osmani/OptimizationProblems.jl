using ADNLPModels, NLPModels, NLPModelsJuMP, OptimizationProblems, Test

include("test_utils.jl")

function set_meta(all::AbstractVector{T}) where {T <: Union{Symbol, String}}
  for name in string.(all)
    io = open("src/Meta/" * name * ".jl", "w")
    write(io, generate_meta(name))
    close(io)
  end
end

function replace_entry_meta(
  all::AbstractVector{T},
  old_entry,
  new_entry,
) where {T <: Union{Symbol, String}}
  for name in string.(all)
    lines = readlines("src/Meta/" * name * ".jl")
    open("src/Meta/" * name * ".jl", "w") do io
      for line in lines
        write(io, replace(line, "$(old_entry)" => "$(new_entry)") * "\n")
      end
    end
  end
end

"""
  `generate_meta(model, name)`
  `generate_meta(name)`
  
  is used to generate the meta of a given NLPModel.
"""
function generate_meta(
  nlp::AbstractNLPModel,
  name::String;
  default_nvar = OptimizationProblems.ADNLPProblems.default_nvar,
)
  contype = if get_ncon(nlp) == 0 && length(get_ifree(nlp)) >= get_nvar(nlp)
    :unconstrained
  elseif get_nlin(nlp) == get_ncon(nlp) > 0
    :linear
  else
    :general
  end
  objtype = :other

  origin = :unknown

  if name in ["clplatea", "clplateb", "clplatec", "fminsrf2"] # issue because variable is a matrix
    variable_nvar, variable_ncon = false, false
    nvar_formula = "$(get_nvar(nlp))"
    ncon_formula = "$(get_ncon(nlp))"
    nlin_formula = "$(get_nlin(nlp))"
    nnln_formula = "$(get_nnln(nlp))"
    nequ_formula = "$(length(get_jfix(nlp)))"
    nineq_formula = "$(get_ncon(nlp) - length(get_jfix(nlp)))"
  else
    variable_nvar, nvar_formula = var_size(name, get_nvar, default_nvar)
    variable_ncon, ncon_formula = var_size(name, get_ncon, default_nvar)
    nlin_formula = var_size(name, get_nlin, default_nvar)[2]
    nnln_formula = var_size(name, get_nnln, default_nvar)[2]
    nequ_formula = var_size(name, nlp -> length(get_jfix(nlp)), default_nvar)[2]
    nineq_formula = var_size(name, nlp -> get_ncon(nlp) - length(get_jfix(nlp)), default_nvar)[2]
  end

  feasible = is_feasible(nlp)
  x0_is_feasible = ismissing(feasible) ? false : feasible
  if get_minimize(nlp)
    bnlb = -Inf
    bnub = x0_is_feasible ? obj(nlp, nlp.meta.x0) : Inf
  else
    bnub = Inf
    bnlb = x0_is_feasible ? obj(nlp, nlp.meta.x0) : -Inf
  end

  str = "$(name)_meta = Dict(
  :nvar => $(get_nvar(nlp)),
  :variable_nvar => $(variable_nvar),
  :ncon => $(get_ncon(nlp)),
  :variable_ncon => $(variable_ncon),
  :minimize => $(get_minimize(nlp)),
  :name => \"$(name)\",
  :has_equalities_only => $(length(get_jfix(nlp)) == get_ncon(nlp) > 0),
  :has_inequalities_only => $(get_ncon(nlp) > 0 && length(get_jfix(nlp)) == 0),
  :has_bounds => $(length(get_ifree(nlp)) < get_nvar(nlp)),
  :has_fixed_variables => $(get_ifix(nlp) != []),
  :objtype => :$(objtype),
  :contype => :$(contype),
  :best_known_lower_bound => $(bnlb),
  :best_known_upper_bound => $(bnub),
  :is_feasible => $(feasible),
  :defined_everywhere => $(missing),
  :origin => :$(origin),
)
get_$(name)_nvar(; n::Integer = default_nvar, kwargs...) = $nvar_formula
get_$(name)_ncon(; n::Integer = default_nvar, kwargs...) = $ncon_formula
get_$(name)_nlin(; n::Integer = default_nvar, kwargs...) = $nlin_formula
get_$(name)_nnln(; n::Integer = default_nvar, kwargs...) = $nnln_formula
get_$(name)_nequ(; n::Integer = default_nvar, kwargs...) = $nequ_formula
get_$(name)_nineq(; n::Integer = default_nvar, kwargs...) = $nineq_formula
"
  return str
end

function generate_meta(name::String, args...; kwargs...)
  nlp = if name != "hs61" && name in string.(names(PureJuMP))
    eval(Meta.parse("MathOptNLPModel(PureJuMP." * name * "())"))
  elseif name in string.(names(ADNLPProblems))
    eval(Meta.parse("ADNLPProblems." * name * "()"))
  else
    eval(Meta.parse(name * "( n = ADNLPProblems.default_nvar)"))
  end
  return generate_meta(nlp, name, args...; kwargs...)
end

function is_feasible(nlp::AbstractNLPModel; x = nlp.meta.x0)
  feasible = missing
  if get_ncon(nlp) == 0
    feasible = true
  else
    c = cons(nlp, x)
    if all(get_lcon(nlp) .<= c .<= get_ucon(nlp)) && all(get_lvar(nlp) .<= x .<= get_uvar(nlp))
      feasible = true
    end
    if any(get_lvar(nlp) .> get_uvar(nlp)) || any(get_lcon(nlp) .> get_ucon(nlp))
      feasible = false
    end
  end
  return feasible
end

function var_size(name::String, get_field::Function, default_nvar)
  n1 = default_nvar
  n2 = div(default_nvar, 2)

  prefix = name in string.(names(ADNLPProblems)) ? "ADNLPProblems." : ""
  nlp1 = eval(Meta.parse(prefix * name))(n = n1)
  nvar1 = get_field(nlp1)
  nlp2 = eval(Meta.parse(prefix * name))(n = n2)
  nvar2 = get_field(nlp2)
  variable_nvar = nvar1 != nvar2
  #Assuming the scale is linear in n
  nvar_formula = if !variable_nvar
    string(nvar1)
  else
    a = div(nvar1 - nvar2, n1 - n2)
    b = nvar2 - a * n2
    "$a * n + $b"
  end
  return variable_nvar, nvar_formula
end

"""
    test_linear_constraints(sample_size = 100)

Return the list of problems where the linear indices where not correctly identified.
"""
function test_linear_constraints(sample_size = 100)
  meta = OptimizationProblems.meta[!, :]
  con_pb = meta[meta.ncon .> 0, :name]
  sample_size = max(sample_size, 2)

  list = []
  for pb in con_pb
    nlp = OptimizationProblems.ADNLPProblems.eval(Symbol(pb))()
    std = similar(nlp.meta.x0)
    blvar = similar(nlp.meta.lvar)
    buvar = similar(nlp.meta.uvar)
    for j = 1:(nlp.meta.nvar)
      blvar[j] = nlp.meta.lvar[j] == -Inf ? -10.0 : nlp.meta.lvar[j]
      buvar[j] = nlp.meta.uvar[j] == Inf ? 10.0 : nlp.meta.uvar[j]
      std[j] = max(abs(blvar[j]), abs(buvar[j]))
    end
    ref = jac(nlp, nlp.meta.x0)
    Iref = collect(1:(nlp.meta.ncon))
    for i = 1:sample_size
      x = min.(max.((2 * rand(nlp.meta.nvar) .- 1) .* std, blvar), buvar)
      cx = jac(nlp, x)
      setdiff!(Iref, findall(j -> cx[j, :] != ref[j, :], 1:(nlp.meta.ncon)))
      if Iref == []
        break
      end
    end
    if Iref != nlp.meta.lin
      push!(list, (nlp.meta.name, Iref))
    end
  end
  return list
end

test_one_problem(pb::String) = test_one_problem(Symbol(pb))
function test_one_problem(prob::Symbol)
  pb = string(prob)
  @info "Check that $prob is in PureJuMP"
  @test prob in names(PureJuMP)
  @info "Check that $prob is in ADNLPProblems"
  @test prob in names(ADNLPProblems)
  @info "Check that $prob in Meta"
  @test string(prob) in OptimizationProblems.meta[!, :name]
  @info "Instantiate default ADNLPModel"
  nlp_ad = eval(Meta.parse("ADNLPProblems.$(prob)()"))
  @info "Test multi-precision ADNLPProblems for $prob"
  test_multi_precision(prob, nlp_ad)
  if pb in meta[
    (meta.contype .== :quadratic) .| (meta.contype .== :general),
    :name,
  ]
    @info "Test In-place Nonlinear Constraints for AD-$prob"
    test_in_place_constraints(prob, nlp_ad)
    # Check to see if there are linear constraints
  end

  if  pb in meta[meta.objtype .== :least_squares, :name]
    @info "Test Nonlinear Least Squares for $prob"
    test_in_place_residual(prob)
  else
    # Test if we suggest that the problem is a NLS
  end

  @info "Instantiate PureJuMP model"
  prob_fn = eval(Meta.parse("PureJuMP.$(prob)"))
  model = prob_fn(n = ndef)
  @info "Instantiate MathOptNLPModel version of the JuMP model"
  nlp_jump = MathOptNLPModel(model)
  @info "Test compatibility between PureJuMP and ADNLPProblems"
  test_compatibility(prob, nlp_jump, nlp_ad, ndef)

end
