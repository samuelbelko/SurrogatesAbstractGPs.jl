module SurrogatesAbstractGPs
# Refactoring and extending registered SurrogatesAbstractGPs package,
# https://github.com/SciML/Surrogates.jl/tree/e6aa022e612ac57228506e625c662438d385e69d/lib/SurrogatesAbstractGPs

# currently SurrogatesBase is from a fork https://github.com/samuelbelko/SurrogatesBase.jl.git
# on branch param-abstract-type
using SurrogatesBase
import SurrogatesBase: add_point!,
    update_hyperparameters!, hyperparameters,
    mean, var, mean_and_var, rand

import AbstractGPs
import KernelFunctions

include("HyperparametersAbstractGPs.jl")
using .HyperparametersAbstractGPs

export BoundedHyperparameters
export GPSurrogate, add_point!
export update_hyperparameters!, hyperparameters
export mean, var, mean_and_var, rand

include("utils.jl")

# GPSurrogate for functions defined on R^n, D has to be constrained, as otherwise it could
# be Any and so the definition of mean would become ambiguous with the one in Statistics
mutable struct GPSurrogate{D <: Union{Number, AbstractVector}, R, GP, GP_P, F} <:
               AbstractSurrogate{D, R}
    xs::Vector{D}
    ys::Vector{R}
    # prior process
    gp::GP
    gp_posterior::GP_P
    hyperparameters::NamedTuple
    kernel_creator::F
end

"""
    GPSurrogate(xs,
        ys;
        kernel_creator = (_ -> KernelFunctions.Matern52Kernel()),
        hyperparameters = (; noise_var = 0.1))

Gaussian process surrogate.

Pass points `xs` with corresponding evaluations in `ys`,
`kernel_creator` function and `hyperparameters` of type `NamedTuple`.

`kernel_creator` needs to map `hyperparameters` into a kernel function as defined by the
package KernelFunctions.jl.

If `hyperparameters` includes an entry with name `noise_var`, then the value of `noise_var`
will be passed directly to `AbstractGPs`, hence the `kernel_creator` should never use
the entry `noise_var` inside `hyperparameters`. Please compare with [Mauna loa example](https://juliagaussianprocesses.github.io/AbstractGPs.jl/stable/examples/1-mauna-loa/#Posterior)
in `AbstractGPs` docs.
"""
function GPSurrogate(xs,
    ys;
    kernel_creator = (_ -> KernelFunctions.Matern52Kernel()),
    hyperparameters = (; noise_var = 0.1))
    # prior process, for safety remove noise_var from hyperparameters when passing to
    # kernel_creator, see docs above
    gp = AbstractGPs.GP(kernel_creator(delete(hyperparameters, :noise_var)))
    # if :noise_var is not in keys(hyperparameters), add entry noise_var = 0.0
    hyperparameters = merge((; noise_var = 0.0), hyperparameters)
    GPSurrogate(xs,
        ys,
        gp,
        AbstractGPs.posterior(gp(xs, hyperparameters.noise_var), ys),
        hyperparameters,
        kernel_creator)
end

# for add_point! copies of xs and ys need to be made because we get
# "Error: cannot resize array with shared data " if we push! directly to xs and ys
function add_point!(g::GPSurrogate{D, R}, new_x::D, new_y::R) where {D, R}
    x_copy = copy(g.xs)
    push!(x_copy, new_x)
    y_copy = copy(g.ys)
    push!(y_copy, new_y)
    updated_posterior = AbstractGPs.posterior(g.gp(x_copy, g.hyperparameters.noise_var),
        y_copy)
    g.xs, g.ys, g.gp_posterior = x_copy, y_copy, updated_posterior
    nothing
end

function add_point!(g::GPSurrogate{D, R}, new_xs::Vector{D}, new_ys::Vector{R}) where {D, R}
    length(new_xs) == length(new_ys) ||
        throw(ArgumentError("new_xs, new_ys have different lengths"))
    x_copy = copy(g.xs)
    append!(x_copy, new_xs)
    y_copy = copy(g.ys)
    append!(y_copy, new_ys)
    updated_posterior = AbstractGPs.posterior(g.gp(x_copy, g.hyperparameters.noise_var),
        y_copy)
    g.xs, g.ys, g.gp_posterior = x_copy, y_copy, updated_posterior
    nothing
end

"""
    update_hyperparameters!(g::GPSurrogate, prior)

Hyperparameter tuning for `GPSurrogate`.

See also [`BoundedHyperparameters`](@ref) that can be used as a prior.
"""
function update_hyperparameters!(g::GPSurrogate, prior)
    # save new hyperparameters
    g.hyperparameters = optimize_hyperparameters(g.xs, g.ys, g.kernel_creator, prior)
    # update GP and its posterior
    g.gp = AbstractGPs.GP(g.kernel_creator(g.hyperparameters))
    g.gp_posterior = AbstractGPs.posterior(g.gp(g.xs, g.hyperparameters.noise_var), g.ys)
    nothing
end

hyperparameters(g::GPSurrogate) = g.hyperparameters

# mean at point, have to add <: Number, otherwise there is ambiguity with mean from Statistics
function mean(g::GPSurrogate{D}, x::D) where {D <: Union{Number, AbstractVector}}
    only(AbstractGPs.mean(g.gp_posterior([x])))
end
# mean at points
function mean(g::GPSurrogate{D}, xs::Vector{D}) where {D <: Union{Number, AbstractVector}}
    AbstractGPs.mean(g.gp_posterior(xs))
end

# variance at point
function var(g::GPSurrogate{D}, x::D) where {D <: Union{Number, AbstractVector}}
    only(AbstractGPs.var(g.gp_posterior([x])))
end
# variance at points
function var(g::GPSurrogate{D}, xs::Vector{D}) where {D <: Union{Number, AbstractVector}}
    AbstractGPs.var(g.gp_posterior(xs))
end

# mean and variance at point
function mean_and_var(g::GPSurrogate{D}, x::D) where {D <: Union{Number, AbstractVector}}
    only.(AbstractGPs.mean_and_var(g.gp_posterior([x])))
end
# mean and variance at points
function mean_and_var(g::GPSurrogate{D},
    x::Vector{D}) where {D <: Union{Number, AbstractVector}}
    AbstractGPs.mean_and_var(g.gp_posterior(x))
end

# sample from joint posterior, use default in SurrogatesBase for "at point" version
function rand(g::GPSurrogate{D}, xs::Vector{D}) where {D <: Union{Number, AbstractVector}}
    rand(g.gp_posterior(xs))
end

end # module
