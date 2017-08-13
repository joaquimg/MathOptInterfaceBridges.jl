function Base.getindex(f::MOI.VectorAffineFunction, i::Integer)
    I = find(oi -> oi == i, f.outputindex)
    MOI.ScalarAffineFunction(f.variables[I], f.coefficients[I], f.constant[i])
end

function Base.getindex(f::MOI.VectorAffineFunction{T}, I::AbstractVector) where T
    outputindex = Int[]
    variables = VR[]
    coefficients = T[]
    constant = Vector{T}(length(I))
    for (i, j) in enumerate(I)
        g = f[j]
        append!(outputindex, repmat(i:i, length(g.variables)))
        append!(variables, g.variables)
        append!(coefficients, g.coefficients)
        constant[i] = g.constant
    end
    MOI.VectorAffineFunction(outputindex, variables, coefficients, constant)
end

# Define copy of function
Base.deepcopy(f::SVF) = f
Base.deepcopy(f::VVF) = VVF(copy(f.variables))
Base.deepcopy(f::SAF) = SAF(copy(f.variables),
                            copy(f.coefficients),
                            f.constant)
Base.deepcopy(f::VAF) = VAF(copy(f.outputindex),
                            copy(f.variables),
                            copy(f.coefficients),
                            f.constant)
Base.deepcopy(f::SQF) = SQF(copy(f.affine_variables),
                            copy(f.affine_coefficients),
                            copy(f.quadratic_rowvariables),
                            copy(f.quadratic_colvariables),
                            copy(f.quadratic_coefficients),
                            f.constant)
Base.deepcopy(f::VQF) = VQF(copy(f.affine_outputindex),
                            copy(f.affine_variables),
                            copy(f.affine_coefficients),
                            copy(f.quadratic_outputindex),
                            copy(f.quadratic_rowvariables),
                            copy(f.quadratic_colvariables),
                            copy(f.quadratic_coefficients),
                            f.constant)

# Utilities for getting a canonical representation of a function
Base.isless(v1::VR, v2::VR) = isless(v1.value, v2.value)
"""
    canonical(f::AbstractFunction)

Returns the funcion in a canonical form, i.e.
* A term appear only once.
* The coefficients are nonzero.
* The terms appear in increasing order of variable where there the order of the variables is the order of their value.
* For a `AbstractVectorFunction`, the terms are sorted in ascending order of output index.

### Examples
If `x` (resp. `y`, `z`) is `VariableReference(1)` (resp. 2, 3).
The canonical representation of `ScalarAffineFunction([y, x, z, x, z], [2, 1, 3, -2, -3], 5)` is `ScalarAffineFunction([x, y], [-1, 2], 5)`.

"""
function canonical{T}(f::SAF{T})
    σ = sortperm(f.variables)
    outputindex = Int[]
    variables = VR[]
    coefficients = T[]
    prev = 0
    for i in σ
        if !isempty(variables) && f.variables[i] == last(variables)
            coefficients[end] += f.coefficients[i]
        elseif !iszero(f.coefficients[i])
            if !isempty(variables) && iszero(last(coefficients))
                variables[end] = f.variables[i]
                coefficients[end] = f.coefficients[i]
            else
                push!(variables, f.variables[i])
                push!(coefficients, f.coefficients[i])
            end
        end
    end
    if !isempty(variables) && iszero(last(coefficients))
        pop!(variables)
        pop!(coefficients)
    end
    SAF{T}(variables, coefficients, f.constant)
end
function canonical{T}(f::VAF{T})
    σ = sortperm(1:length(f.variables), by = i -> (f.outputindex[i], f.variables[i]))
    outputindex = Int[]
    variables = VR[]
    coefficients = T[]
    prev = 0
    for i in σ
        if !isempty(variables) && f.outputindex[i] == last(outputindex) && f.variables[i] == last(variables)
            coefficients[end] += f.coefficients[i]
        elseif !iszero(f.coefficients[i])
            if !isempty(variables) && iszero(last(coefficients))
                outputindex[end] = f.outputindex[i]
                variables[end] = f.variables[i]
                coefficients[end] = f.coefficients[i]
            else
                push!(outputindex, f.outputindex[i])
                push!(variables, f.variables[i])
                push!(coefficients, f.coefficients[i])
            end
        end
    end
    if !isempty(variables) && iszero(last(coefficients))
        pop!(outputindex)
        pop!(variables)
        pop!(coefficients)
    end
    VAF{T}(outputindex, variables, coefficients, f.constant)
end

# Utilities for comparing functions
# Define isapprox so that we can use ≈ in tests

function _isapprox(vars1, coeffs1, vars2, coeffs2; kwargs...)
    m = length(vars1)
    n = length(vars2)
    i = 1
    j = 1
    while i <= m || j <= n
        if i <= m && j <= n && vars1[i] == vars2[j]
            isapprox(coeffs1[i], coeffs2[j]; kwargs...) || return false
            i += 1
            j += 1
        elseif j > n || (i <= m && vars1[i] < vars2[j])
            isapprox(coeffs1[i], 0.0; kwargs...) || return false
            i += 1
        else
            isapprox(0.0, coeffs2[j]; kwargs...) || return false
            j += 1
        end
    end
    return true
end

function Base.isapprox(f1::MOI.VectorAffineFunction, f2::MOI.VectorAffineFunction; kwargs...)
    f1 = canonical(f1)
    f2 = canonical(f2)
    _isapprox(collect(zip(f1.outputindex, f1.variables)), f1.coefficients, collect(zip(f2.outputindex, f2.variables)), f2.coefficients; kwargs...)
end

function Base.isapprox(f1::MOI.ScalarAffineFunction, f2::MOI.ScalarAffineFunction; kwargs...)
    f1 = canonical(f1)
    f2 = canonical(f2)
    _isapprox(f1.variables, f1.coefficients, f2.variables, f2.coefficients; kwargs...)
end

function Base.isapprox(f1::MOI.ScalarAffineFunction{T}, f2::MOI.ScalarAffineFunction{T}; kwargs...) where {T}
    function canonicalize(f)
        d = Dict{MOI.VariableReference,T}()
        @assert length(f.variables) == length(f.coefficients)
        for k in 1:length(f.variables)
            d[f.variables[k]] = f.coefficients[k] + get(d, f.variables[k], zero(T))
        end
        return (d,f.constant)
    end
    d1, c1 = canonicalize(f1)
    d2, c2 = canonicalize(f2)
    for (var,coef) in d2
        d1[var] = get(d1,var,zero(T)) - coef
    end
    return isapprox([c2-c1;collect(values(d1))], zeros(T,length(d1)+1); kwargs...)
end

function Base.isapprox(f1::MOI.ScalarQuadraticFunction{T}, f2::MOI.ScalarQuadraticFunction{T}; kwargs...) where {T}
    function canonicalize(f)
        affine_d = Dict{MOI.VariableReference,T}()
        @assert length(f.affine_variables) == length(f.affine_coefficients)
        for k in 1:length(f.affine_variables)
            affine_d[f.affine_variables[k]] = f.affine_coefficients[k] + get(affine_d, f.affine_variables[k], zero(T))
        end
        quadratic_d = Dict{Set{MOI.VariableReference},T}()
        @assert length(f.quadratic_rowvariables) == length(f.quadratic_coefficients)
        @assert length(f.quadratic_colvariables) == length(f.quadratic_coefficients)
        for k in 1:length(f.quadratic_rowvariables)
            quadratic_d[Set([f.quadratic_rowvariables[k],f.quadratic_colvariables[k]])] = f.quadratic_coefficients[k] + get(quadratic_d, Set([f.quadratic_rowvariables[k],f.quadratic_colvariables[k]]), zero(T))
        end
        return (quadratic_d,affine_d,f.constant)
    end
    quad_d1, aff_d1, c1 = canonicalize(f1)
    quad_d2, aff_d2, c2 = canonicalize(f2)
    for (var,coef) in aff_d2
        aff_d1[var] = get(aff_d1,var,zero(T)) - coef
    end
    for (vars,coef) in quad_d2
        quad_d1[vars] = get(quad_d1,vars,zero(T)) - coef
    end
    return isapprox([c2-c1;collect(values(aff_d1));collect(values(quad_d1))], zeros(T,length(quad_d1)+length(aff_d1)+1); kwargs...)
end


function _rmvar(vrs::Vector{MOI.VariableReference}, vr::MOI.VariableReference)
    find(v -> v != vr, vrs)
end
function _rmvar(vrs1::Vector{MOI.VariableReference}, vrs2::Vector{MOI.VariableReference}, vr::MOI.VariableReference)
    @assert eachindex(vrs1) == eachindex(vrs2)
    find(i -> vrs1[i] != vr && vrs2[i] != vr, eachindex(vrs1))
end

"""
    removevariable(f::AbstractFunction, vr::VariableReference)

Return a new function `f` with the variable vr removed.
"""
function removevariable(f::MOI.VectorOfVariables, vr)
    MOI.VectorOfVariables(f.variables[_rmvar(f.variables, vr)])
end
function removevariable(f::MOI.ScalarAffineFunction, vr)
    I = _rmvar(f.variables, vr)
    MOI.ScalarAffineFunction(f.variables[I], f.coefficients[I], f.constant)
end
function removevariable(f::MOI.ScalarQuadraticFunction, vr)
    I = _rmvar(f.affine_variables, vr)
    J = _rmvar(f.quadratic_rowvariables, f.quadratic_colvariables, vr)
    MOI.ScalarQuadraticFunction(f.affine_variables[I], f.affine_coefficients[I],
                                f.quadratic_rowvariables[J], f.quadratic_colvariables[J], f.quadratic_coefficients[J],
                                f.constant)
end
function removevariable(f::MOI.VectorAffineFunction, vr)
    I = _rmvar(f.variables, vr)
    MOI.VectorAffineFunction(f.outputindex[I], f.variables[I], f.coefficients[I], f.constant)
end
function removevariable(f::MOI.VectorQuadraticFunction, vr)
    I = _rmvar(f.affine_variables, vr)
    J = _rmvar(f.quadratic_rowvariables, f.quadratic_colvariables, vr)
    MOI.VectorQuadraticFunction(f.affine_outputindex[I], f.affine_variables[I], f.affine_coefficients[I],
                                f.quadratic_outputindex[J], f.quadratic_rowvariables[J], f.quadratic_colvariables[J], f.quadratic_coefficients[J],
                                f.constant)
end

"""
    modifyfunction(f::AbstractFunction, change::AbstractFunctionModification)

Return a new function `f` modified according to `change`.
"""
function modifyfunction(f::MOI.ScalarAffineFunction, change::MOI.ScalarConstantChange)
    MOI.ScalarAffineFunction(f.variables, f.coefficients, change.new_constant)
end
function modifyfunction(f::MOI.ScalarQuadraticFunction, change::MOI.ScalarConstantChange)
    MOI.ScalarQuadraticFunction(f.affine_variables, f.affine_coefficients,
                         f.quadratic_rowvariables, f.quadratic_colvariables, f.quadratic_coefficients,
                         change.new_constant)
end

function modifyfunction(f::MOI.VectorAffineFunction, change::MOI.VectorConstantChange)
    MOI.VectorAffineFunction(f.outputindex, f.variables, f.coefficients, change.new_constant)
end
function modifyfunction(f::MOI.VectorQuadraticFunction, change::MOI.VectorConstantChange)
    MOI.VectorQuadraticFunction(f.affine_outputindex, f.affine_variables, f.affine_coefficients,
                                f.quadratic_outputindex, f.quadratic_rowvariables, f.quadratic_colvariables, f.quadratic_coefficients,
                                change.new_constant)
end

function _modifycoefficient(variables::Vector{MOI.VariableReference}, coefficients::Vector, variable::MOI.VariableReference, new_coefficient)
    variables = copy(variables)
    coefficients = copy(coefficients)
    i = findfirst(variables, variable)
    if i == 0
        # The variable was not already in the function
        if !iszero(new_coefficient)
            push!(variables, variable)
            push!(coefficients, new_coefficient)
        end
    else
        # The variable was already in the function
        if iszero(new_coefficient)
            deleteat!(variables, i)
            deleteat!(coefficients, i)
        else
            coefficients[i] = new_coefficient
        end
    end
    variables, coefficients
end
function modifyfunction(f::MOI.ScalarAffineFunction, change::MOI.ScalarCoefficientChange)
    MOI.ScalarAffineFunction(_modifycoefficient(f.variables, f.coefficients, change.variable, change.new_coefficient)..., f.constant)
end
function modifyfunction(f::MOI.ScalarQuadraticFunction, change::MOI.ScalarCoefficientChange)
    MOI.ScalarQuadraticFunction(_modifycoefficient(f.affine_variables, f.affine_coefficients, change.variable, change.new_coefficient)...,
                            f.quadratic_rowvariables, f.quadratic_colvariables, f.quadratic_coefficients,
                            f.constant)

end
function _modifycoefficients(n, outputindex, variables::Vector{MOI.VariableReference}, coefficients::Vector, variable::MOI.VariableReference, rows, new_coefficients)
    outputindex = copy(outputindex)
    variables = copy(variables)
    coefficients = copy(coefficients)
    rowmap = zeros(Int, n)
    rowmap[rows] = 1:length(rows)
    del = Int[]
    for i in 1:length(variables)
        if variables[i] == variable
            row = outputindex[i]
            j = rowmap[row]
            if !iszero(j)
                if iszero(new_coefficients[j])
                    push!(del, i)
                else
                    coefficients[i] =  new_coefficients[j]
                end
                rowmap[row] = 0
            end
        end
    end
    deleteat!(outputindex, del)
    deleteat!(variables, del)
    deleteat!(coefficients, del)
    for (row, j) in enumerate(rowmap)
        if !iszero(j)
            push!(outputindex, row)
            push!(variables, variable)
            push!(coefficients, new_coefficients[j])
        end
    end
    outputindex, variables, coefficients
end
function modifyfunction(f::MOI.VectorAffineFunction, change::MOI.MultirowChange)
    MOI.VectorAffineFunction(_modifycoefficients(length(f.constant), f.outputindex, f.variables, f.coefficients, change.variable, change.rows, change.new_coefficients)...,
                         f.constant)
end
function modifyfunction(f::MOI.VectorQuadraticFunction, change::MOI.MultirowChange)
    MOI.VectorQuadraticFunction(_modifycoefficients(length(f.constant), f.affine_outputindex, f.affine_variables, f.affine_coefficients, change.variable, change.rows, change.new_coefficients)...,
                            f.quadratic_outputindex, f.quadratic_rowvariables, f.quadratic_colvariables, f.quadratic_coefficients,
                            f.constant)
end
