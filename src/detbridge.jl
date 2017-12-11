function trimap(i::Integer, j::Integer)
    if i < j
        trimap(j, i)
    else
        div((i-1)*i, 2) + j
    end
end

"""
    extract_eigenvalues(instance, f::MOI.VectorAffineFunction{T}, d::Int) where T

The vector `f` contains `t` followed by the matrix `X` of dimension `d`.
This functions extracts the eigenvalues of `X` and returns `t`,
a vector `MOI.VariableIndex` containing the eigenvalues of `X`,
the variables created and the index of the constraint created to extract the eigenvalues.
"""
function extract_eigenvalues(instance, f::MOI.VectorAffineFunction{T}, d::Int) where T
    n = trimap(d, d)
    N = trimap(2d, 2d)

    Δ = MOI.addvariables!(instance, n)

    X = eachscalar(f)[2:(n+1)]
    m = length(X.outputindex)
    M = m + n + d

    outputindex = Vector{Int}(M); outputindex[1:m] = X.outputindex
    variables = Vector{VI}(M); variables[1:m] = X.variables
    coefficients = Vector{T}(M); coefficients[1:m] = X.coefficients
    constant = zeros(T, N); constant[1:n] = X.constant

    cur = m
    for j in 1:d
        for i in j:d
            cur += 1
            outputindex[cur] = trimap(i, d+j)
            variables[cur] = Δ[trimap(i, j)]
            coefficients[cur] = one(T)
        end
        cur += 1
        outputindex[cur] = trimap(d+j, d+j)
        variables[cur] = Δ[trimap(j, j)]
        coefficients[cur] = one(T)
    end
    @assert cur == M
    Y = MOI.VectorAffineFunction(outputindex, variables, coefficients, constant)
    sdindex = MOI.addconstraint!(instance, Y, MOI.PositiveSemidefiniteConeTriangle(2d))

    t = eachscalar(f)[1]
    D = Δ[trimap.(1:d, 1:d)]
    t, D, Δ, sdindex
end

"""
    LogDetBridge{T}

The `LogDetConeTriangle` is representable by a `PositiveSemidefiniteConeTriangle` and `ExponentialCone` constraints.
Indeed, ``\\log\\det(X) = \\log(\\delta_1) + \\cdots + \\log(\\delta_n)`` where ``\\delta_1``, ..., ``\\delta_n`` are the eigenvalues of ``X`.
Adapting, the method from [1, p. 149], we see that ``t \\le \\log(\\det(X))`` if and only if there exists a lower triangular matrix ``Δ`` such that
```math
\\begin{align*}
  \\begin{pmatrix}
    X & Δ\\\\
    Δ^\\top & \\mathrm{Diag}(Δ)
  \\end{pmatrix} & \\succeq 0\\\\
  t & \\le \\log(Δ_{11}) + \\log(Δ_{22}) + \\cdots + \\log(Δ_{nn})
\\end{align*}

[1] Ben-Tal, Aharon, and Arkadi Nemirovski. *Lectures on modern convex optimization: analysis, algorithms, and engineering applications*. Society for Industrial and Applied Mathematics, 2001.
```
"""
struct LogDetBridge{T} <: AbstractBridge
    Δ::Vector{VI}
    l::Vector{VI}
    sdindex::CI{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}
    lcindex::Vector{CI{MOI.VectorAffineFunction{T}, MOI.ExponentialCone}}
    tlindex::CI{MOI.ScalarAffineFunction{T}, MOI.LessThan{T}}
end
function LogDetBridge{T}(instance, f::MOI.VectorOfVariables, s::MOI.LogDetConeTriangle) where T
    LogDetBridge{T}(instance, MOI.VectorAffineFunction{T}(f), s)
end
function LogDetBridge{T}(instance, f::MOI.VectorAffineFunction{T}, s::MOI.LogDetConeTriangle) where T
    d = s.dimension
    t, D, Δ, sdindex = extract_eigenvalues(instance, f, d)
    l = MOI.addvariables!(instance, d)
    lcindex = sublog.(instance, l, D, T)
    tlindex = subsum(instance, t, l, T)

    LogDetBridge(Δ, l, sdindex, lcindex, tlindex)
end

"""
    sublog(instance, x::MOI.VariableIndex, z::MOI.VariableIndex, ::Type{T}) where T

Constrains ``x \\le \\log(z)`` and return the constraint index.
"""
function sublog(instance, x::MOI.VariableIndex, z::MOI.VariableIndex, ::Type{T}) where T
    MOI.addconstraint!(instance, MOI.VectorAffineFunction([1, 3], [x, z], ones(T, 2), [zero(T), one(T), zero(T)]), MOI.ExponentialCone())
end

"""
    subsum(instance, t::MOI.ScalarAffineFunction, l::Vector{MOI.VariableIndex}, ::Type{T}) where T

Constrains ``t \\le l_1 + \\cdots + l_n`` where `n` is the length of `l` and return the constraint index.
"""
function subsum(instance, t::MOI.ScalarAffineFunction, l::Vector{MOI.VariableIndex}, ::Type{T}) where T
    n = length(l)
    MOI.addconstraint!(instance, MOI.ScalarAffineFunction([t.variables; l], [t.coefficients; fill(-one(T), n)], zero(T)), MOI.LessThan(-t.constant))
end

# Attributes, Bridge acting as an instance
MOI.get(b::LogDetBridge, ::MOI.NumberOfVariables) = length(b.Δ) + length(b.l)
MOI.get(b::LogDetBridge{T}, ::MOI.NumberOfConstraints{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}) where T = 1
MOI.get(b::LogDetBridge{T}, ::MOI.NumberOfConstraints{MOI.VectorAffineFunction{T}, MOI.ExponentialCone}) where T = length(b.lcindex)
MOI.get(b::LogDetBridge{T}, ::MOI.NumberOfConstraints{MOI.ScalarAffineFunction{T}, MOI.LessThan{T}}) where T = 1
MOI.get(b::LogDetBridge{T}, ::MOI.ListOfConstraintIndices{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}) where T = [b.sdindex]
MOI.get(b::LogDetBridge{T}, ::MOI.ListOfConstraintIndices{MOI.VectorAffineFunction{T}, MOI.ExponentialCone}) where T = b.lcindex
MOI.get(b::LogDetBridge{T}, ::MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{T}, MOI.LessThan{T}}) where T = [b.tlindex]

# References
function MOI.delete!(instance::MOI.AbstractInstance, c::LogDetBridge)
    MOI.delete!(instance, c.tlindex)
    MOI.delete!(instance, c.lcindex)
    MOI.delete!(instance, c.sdindex)
    MOI.delete!(instance, c.l)
    MOI.delete!(instance, c.Δ)
end

# Attributes, Bridge acting as a constraint
MOI.canget(instance::MOI.AbstractInstance, a::MOI.ConstraintPrimal, c::LogDetBridge) = true
function MOI.get(instance::MOI.AbstractInstance, a::MOI.ConstraintPrimal, c::LogDetBridge)
    d = length(c.lcindex)
    Δ = MOI.get(instance, MOI.VariablePrimal(), c.Δ)[1]
    t = MOI.get(instance, MOI.ConstraintPrimal(), c.tlindex) - sum(log.(Δ[trimap.(1:d, 1:d)]))
    x = MOI.get(instance, MOI.ConstraintPrimal(), c.sdindex)[1:length(c.Δ)]
    [t; x]
end
MOI.canget(instance::MOI.AbstractInstance, a::MOI.ConstraintDual, c::LogDetBridge) = false

# Constraints
MOI.canmodifyconstraint(instance::MOI.AbstractInstance, c::LogDetBridge, change) = false

"""
    RootDetBridge{T}

The `RootDetConeTriangle` is representable by a `PositiveSemidefiniteConeTriangle` and an `GeometricMeanCone` constraints; see [1, p. 149].
Indeed, ``t \\le \\det(X)^(1/n)`` if and only if there exists a lower triangular matrix ``Δ`` such that
```math
\\begin{align*}
  \\begin{pmatrix}
    X & Δ\\\\
    Δ^\\top & \\mathrm{Diag}(Δ)
  \\end{pmatrix} & \\succeq 0\\\\
  t & \\le (Δ_{11} Δ_{22} \\cdots Δ_{nn})^{1/n}
\\end{align*}
```

[1] Ben-Tal, Aharon, and Arkadi Nemirovski. *Lectures on modern convex optimization: analysis, algorithms, and engineering applications*. Society for Industrial and Applied Mathematics, 2001.
"""
struct RootDetBridge{T} <: AbstractBridge
    Δ::Vector{VI}
    sdindex::CI{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}
    gmindex::CI{MOI.VectorAffineFunction{T}, MOI.GeometricMeanCone}
end
function RootDetBridge{T}(instance, f::MOI.VectorOfVariables, s::MOI.RootDetConeTriangle) where T
    RootDetBridge{T}(instance, MOI.VectorAffineFunction{T}(f), s)
end
function RootDetBridge{T}(instance, f::MOI.VectorAffineFunction{T}, s::MOI.RootDetConeTriangle) where T
    d = s.dimension
    t, D, Δ, sdindex = extract_eigenvalues(instance, f, d)
    DF = MOI.VectorAffineFunction{T}(MOI.VectorOfVariables(D))
    gmindex = MOI.addconstraint!(instance, moivcat(t, DF), MOI.GeometricMeanCone(d+1))

    RootDetBridge(Δ, sdindex, gmindex)
end

# Attributes, Bridge acting as an instance
MOI.get(b::RootDetBridge, ::MOI.NumberOfVariables) = length(b.Δ)
MOI.get(b::RootDetBridge{T}, ::MOI.NumberOfConstraints{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}) where T = 1
MOI.get(b::RootDetBridge{T}, ::MOI.NumberOfConstraints{MOI.VectorAffineFunction{T}, MOI.GeometricMeanCone}) where T = 1
MOI.get(b::RootDetBridge{T}, ::MOI.ListOfConstraintIndices{MOI.VectorAffineFunction{T}, MOI.PositiveSemidefiniteConeTriangle}) where T = [b.sdindex]
MOI.get(b::RootDetBridge{T}, ::MOI.ListOfConstraintIndices{MOI.VectorAffineFunction{T}, MOI.GeometricMeanCone}) where T = [b.gmindex]

# References
function MOI.delete!(instance::MOI.AbstractInstance, c::RootDetBridge)
    MOI.delete!(instance, c.gmindex)
    MOI.delete!(instance, c.sdindex)
    MOI.delete!(instance, c.Δ)
end

# Attributes, Bridge acting as a constraint
MOI.canget(instance::MOI.AbstractInstance, a::MOI.ConstraintPrimal, c::RootDetBridge) = true
function MOI.get(instance::MOI.AbstractInstance, a::MOI.ConstraintPrimal, c::RootDetBridge)
    t = MOI.get(instance, MOI.ConstraintPrimal(), c.gmindex)[1]
    x = MOI.get(instance, MOI.ConstraintPrimal(), c.sdindex)[1:length(c.Δ)]
    [t; x]
end
MOI.canget(instance::MOI.AbstractInstance, a::MOI.ConstraintDual, c::RootDetBridge) = false

# Constraints
MOI.canmodifyconstraint(instance::MOI.AbstractInstance, c::RootDetBridge, change) = false