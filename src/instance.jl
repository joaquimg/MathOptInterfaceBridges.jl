const MOIU = MathOptInterfaceUtilities
const C{F, S} = Tuple{CR{F, S}, F, S}

const EMPTYSTRING = ""

# Implementation of MOI for vector of constraint
function _addconstraint!{F, S}(constrs::Vector{C{F, S}}, cr::CR, f::F, s::S)
    push!(constrs, (cr, f, s))
    length(constrs)
end

function _delete!(constrs::Vector, cr::CR, i::Int)
    deleteat!(constrs, i)
    @view constrs[i:end] # will need to shift it in constrmap
end

_getfun(cr::CR, f::MOI.AbstractFunction, s::MOI.AbstractSet) = f
function _getfunction(constrs::Vector, cr::CR, i::Int)
    @assert cr.value == constrs[i][1].value
    _getfun(constrs[i]...)
end

_gets(cr::CR, f::MOI.AbstractFunction, s::MOI.AbstractSet) = s
function _getset(constrs::Vector, cr::CR, i::Int)
    @assert cr.value == constrs[i][1].value
    _gets(constrs[i]...)
end

_modifyconstr{F, S}(cr::CR{F, S}, f::F, s::S, change::F) = (cr, change, s)
_modifyconstr{F, S}(cr::CR{F, S}, f::F, s::S, change::S) = (cr, f, change)
_modifyconstr{F, S}(cr::CR{F, S}, f::F, s::S, change::MOI.AbstractFunctionModification) = (cr, modifyfunction(f, change), s)
function _modifyconstraint!{F, S}(constrs::Vector{C{F, S}}, cr::CR{F}, i::Int, change)
    constrs[i] = _modifyconstr(constrs[i]..., change)
end

_getnoc{F, S}(constrs::Vector{C{F, S}}, noc::MOI.NumberOfConstraints{F, S}) = length(constrs)

function _getloc{F, S}(constrs::Vector{C{F, S}})::Vector{Tuple{DataType, DataType}}
    isempty(constrs) ? [] : [(F, S)]
end

_getlocr(constrs::Vector{C{F, S}}, ::MOI.ListOfConstraintReferences{F, S}) where {F, S} = map(constr -> constr[1], constrs)
_getlocr(constrs::Vector{<:C}, ::MOI.ListOfConstraintReferences{F, S}) where {F, S} = CR{F, S}[]

# Implementation of MOI for AbstractInstance
abstract type AbstractInstance{T} <: MOI.AbstractStandaloneInstance end

getconstrloc(m::AbstractInstance, cr::CR) = m.constrmap[cr.value]

# Variables
MOI.get(m::AbstractInstance, ::MOI.NumberOfVariables) = m.nvars
MOI.addvariable!(m::AbstractInstance) = MOI.VariableReference(m.nvars += 1)
function MOI.addvariables!(m::AbstractInstance, n::Integer)
    [MOI.addvariable!(m) for i in 1:n]
end

function _removevar(cr::CR, f, s, vr::MOI.VariableReference)
    (cr, removevariable(f, vr), s)
end
function _removevar(cr::CR, f::MOI.VectorOfVariables, s, vr::MOI.VariableReference)
    g = removevariable(f, vr)
    if length(g.variables) != length(f.variables)
        t = updatedimension(s, length(g.variables))
    else
        t = s
    end
    (cr, g, t)
end
function _removevar!(constrs::Vector, vr::MOI.VariableReference)
    for i in eachindex(constrs)
        constrs[i] = _removevar(constrs[i]..., vr)
    end
    []
end
function _removevar!(constrs::Vector{<:C{MOI.SingleVariable}}, vr::MOI.VariableReference)
    # If a variable is removed, the SingleVariable constraints using this variable
    # need to be removed too
    rm = []
    for (cr, f, s) in constrs
        if f.variable == vr
            push!(rm, cr)
        end
    end
    rm
end
function MOI.delete!(m::AbstractInstance, vr::MOI.VariableReference)
    m.objective = removevariable(m.objective, vr)
    rm = broadcastvcat(constrs -> _removevar!(constrs, vr), m)
    for cr in rm
        MOI.delete!(m, cr)
    end
    if haskey(m.varnames, vr.value)
        delete!(m.namesvar, m.varnames[vr.value])
        delete!(m.varnames, vr.value)
    end
end

MOI.isvalid(m::AbstractInstance, cr::MOI.ConstraintReference) = !iszero(m.constrmap[cr.value])

# Names
MOI.canset(m::AbstractInstance, ::MOI.VariableName, ::VR) = true
function MOI.set!(m::AbstractInstance, ::MOI.VariableName, vr::VR, name::String)
    m.varnames[vr.value] = name
    m.namesvar[name] = vr
end
MOI.canget(m::AbstractInstance, ::MOI.VariableName, ::VR) = true
MOI.get(m::AbstractInstance, ::MOI.VariableName, vr::VR) = get(m.varnames, vr.value, EMPTYSTRING)

MOI.canget(m::AbstractInstance, ::Type{VR}, name::String) = haskey(m.namesvar, name)
MOI.get(m::AbstractInstance, ::Type{VR}, name::String) = m.namesvar[name]

MOI.canset(m::AbstractInstance, ::MOI.ConstraintName, ::CR) = true
function MOI.set!(m::AbstractInstance, ::MOI.ConstraintName, cr::CR, name::String)
    m.connames[cr.value] = name
    m.namescon[name] = cr
end
MOI.canget(m::AbstractInstance, ::MOI.ConstraintName, ::CR) = true
MOI.get(m::AbstractInstance, ::MOI.ConstraintName, cr::CR) = get(m.connames, cr.value, EMPTYSTRING)

MOI.canget(m::AbstractInstance, ::Type{<:CR}, name::String) = haskey(m.namescon, name)
MOI.get(m::AbstractInstance, ::Type{<:CR}, name::String) = m.namescon[name]

# Objective
MOI.get(m::AbstractInstance, ::MOI.ObjectiveSense) = m.sense
function MOI.set!(m::AbstractInstance, ::MOI.ObjectiveFunction, f::MOI.AbstractFunction)
    # f needs to be copied, see #2
    m.objective = deepcopy(f)
end
MOI.get(m::AbstractInstance, ::MOI.ObjectiveFunction) = m.objective
function MOI.set!(m::AbstractInstance, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    m.sense = sense
end

MOI.canmodifyobjective(m::AbstractInstance, change::MOI.AbstractFunctionModification) = true
function MOI.modifyobjective!(m::AbstractInstance, change::MOI.AbstractFunctionModification)
    m.objective = modifyfunction(m.objective, change)
end

# Constraints
function MOI.addconstraint!(m::AbstractInstance, f::F, s::S) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}
    cr = CR{F, S}(m.nconstrs += 1)
    # f needs to be copied, see #2
    push!(m.constrmap, _addconstraint!(m, cr, deepcopy(f), deepcopy(s)))
    cr
end

MOI.candelete(m::AbstractInstance, cr::Union{CR, VR}) = true
function MOI.delete!(m::AbstractInstance, cr::CR)
    for (cr_next, _, _) in _delete!(m, cr, getconstrloc(m, cr))
        m.constrmap[cr_next.value] -= 1
    end
    m.constrmap[cr.value] = 0
    if haskey(m.connames, cr.value)
        delete!(m.namescon, m.connames[cr.value])
        delete!(m.connames, cr.value)
    end
end

MOI.canmodifyconstraint(m::AbstractInstance, cr::CR, change) = true
function MOI.modifyconstraint!(m::AbstractInstance, cr::CR, change)
    _modifyconstraint!(m, cr, getconstrloc(m, cr), change)
end

MOI.get(m::AbstractInstance, noc::MOI.NumberOfConstraints) = _getnoc(m, noc)

function MOI.get(m::AbstractInstance, loc::MOI.ListOfConstraints)
    broadcastvcat(_getloc, m)
end

function MOI.get(m::AbstractInstance, loc::MOI.ListOfConstraintReferences)
    broadcastvcat(constrs -> _getlocr(constrs, loc), m)
end

MOI.canget(m::AbstractInstance, ::Union{MOI.NumberOfVariables,
                                                 MOI.NumberOfConstraints,
                                                 MOI.ListOfConstraints,
                                                 MOI.ListOfConstraintReferences,
                                                 MOI.ObjectiveFunction,
                                                 MOI.ObjectiveSense}) = true

MOI.canget(m::AbstractInstance, ::Union{MOI.ConstraintFunction,
                                                 MOI.ConstraintSet}, ref::MOI.AnyReference) = true

function MOI.get(m::AbstractInstance, ::MOI.ConstraintFunction, cr::CR)
    _getfunction(m, cr, getconstrloc(m, cr))
end

function MOI.get(m::AbstractInstance, ::MOI.ConstraintSet, cr::CR)
    _getset(m, cr, getconstrloc(m, cr))
end

# Can be used to access constraints of an instance
"""
    broadcastcall(f::Function, m::AbstractInstance)

Calls `f(contrs)` for every vector `constrs::Vector{ConstraintReference{F, S}, F, S}` of the instance.

# Examples

To add all constraints of the instance to a solver `solver`, one can do
```julia
_addcon(solver, cr, f, s) = MOI.addconstraint!(solver, f, s)
function _addcon(solver, constrs::Vector)
    for constr in constrs
        _addcon(solver, constr...)
    end
end
MOIU.broadcastcall(constrs -> _addcon(solver, constrs), instance)
```
"""
function broadcastcall end
"""
    broadcastvcat(f::Function, m::AbstractInstance)

Calls `f(contrs)` for every vector `constrs::Vector{ConstraintReference{F, S}, F, S}` of the instance and concatenate the results with `vcat` (this is used internally for `ListOfConstraints`).

# Examples

To get the list of all functions:
```julia
_getfun(cr, f, s) = f
_getfun(crfs::Tuple) = _getfun(crfs...)
_getfuns(constrs::Vector) = _getfun.(constrs)
MOIU.broadcastvcat(_getfuns, instance)
"""
function broadcastvcat end

# Macro to generate Instance
abstract type Constraints{F} end

abstract type SymbolFS end
struct SymbolFun <: SymbolFS
    s::Symbol
    typed::Bool
    cname::Symbol
end
struct SymbolSet <: SymbolFS
    s::Symbol
    typed::Bool
end

# QuoteNode prevents s from being interpolated and keeps it as a symbol
# Expr(:., MOI, s) would be MOI.s
# Expr(:., MOI, $s) would be Expr(:., MOI, EqualTo)
# Expr(:., MOI, :($s)) would be Expr(:., MOI, :EqualTo)
# Expr(:., MOI, :($(QuoteNode(s)))) is Expr(:., MOI, :(:EqualTo)) <- what we want
_mod(m, s::Symbol) = Expr(:., m, :($(QuoteNode(s))))
_set(s::SymbolSet) = _mod(MathOptInterface, s.s)
_fun(s::SymbolFun) = _mod(MathOptInterface, s.s)

_field(s::SymbolFS) = Symbol(lowercase(string(s.s)))

function _getC(s::SymbolSet)
    if s.typed
        :(MathOptInterfaceUtilities.C{F, $(_set(s)){T}})
    else
        :(MathOptInterfaceUtilities.C{F, $(_set(s))})
    end
end
function _getC(s::SymbolFun)
    if s.typed
        :($(_fun(s)){T})
    else
        _fun(s)
    end
end


_getCV(s::SymbolSet) = :($(_getC(s))[])
_getCV(s::SymbolFun) = :($(s.cname){T, $(_getC(s))}())

_callfield(f, s::SymbolFS) = :($f(m.$(_field(s))))
_broadcastfield(b, s::SymbolFS) = :($b(f, m.$(_field(s))))

"""
    macro instance(instancename, scalarsets, typedscalarsets, vectorsets, typedvectorsets, scalarfunctions, vectorfunctions)

Creates a type Instance implementing the MOI instance interface and containing `scalarsets` scalar sets `typedscalarsets` typed scalar sets, `vectorsets` vector sets, `typedvectorsets` typed vector sets, `scalarfunctions` scalar functions and `vectorfunctions` vector functions.
To give no set/function, write `()`, to give one set `S`, write `(S,)`.

### Examples

The instance describing an linear program would be:
```
@instance LPInstance () (EqualTo, GreaterThan, LessThan, Interval) (Zeros, Nonnegatives, Nonpositives) () (SingleVariable,) (ScalarAffineFunction,) (VectorOfVariables,) (VectorAffineFunction,)
```

Let `MOI` denote `MathOptInterface`, `MOIU` denote `MathOptInterfaceUtilities` and `MOIU.C{F, S}` be defined as `MOI.Tuple{CR{F, S}, F, S}`.
The macro would create the types:
```julia
struct LPInstanceScalarConstraints{T, F <: MOI.AbstractScalarFunction} <: MOIU.Constraints{F}
    equalto::Vector{MOIU.C{F, MOI.EqualTo{T}}}
    greaterthan::Vector{MOIU.C{F, MOI.GreaterThan{T}}}
    lessthan::Vector{MOIU.C{F, MOI.LessThan{T}}}
    interval::Vector{MOIU.C{F, MOI.Interval{T}}}
end
struct LPInstanceVectorConstraints{T, F <: MOI.AbstractVectorFunction} <: MOIU.Constraints{F}
    zeros::Vector{MOIU.C{F, MOI.Zeros}}
    nonnegatives::Vector{MOIU.C{F, MOI.Nonnegatives}}
    nonpositives::Vector{MOIU.C{F, MOI.Nonpositives}}
end
mutable struct LPInstance{T} <: MOIU.AbstractInstance{T}
    sense::MOI.OptimizationSense
    objective::Union{MOI.SingleVariable, MOI.ScalarAffineFunction{T}, MOI.ScalarQuadraticFunction{T}}
    nvars::UInt64
    varnames::Dict{UInt64, String}
    namesvar::Dict{String, UInt64}
    nconstrs::UInt64
    constrmap::Vector{Int}
    singlevariable::LPInstanceScalarConstraints{T, MOI.SingleVariable}
    scalaraffinefunction::LPInstanceScalarConstraints{T, MOI.ScalarAffineFunction{T}}
    vectorofvariables::LPInstanceVectorConstraints{T, MOI.VectorOfVariables}
    vectoraffinefunction::LPInstanceVectorConstraints{T, MOI.VectorAffineFunction{T}}
end
```
The type `LPInstance` implements the MathOptInterface API except methods specific to solver instances like `optimize!` or `getattribute` with `VariablePrimal`.
"""
macro instance(instancename, ss, sst, vs, vst, sf, sft, vf, vft)
    scalarsets = [SymbolSet.(ss.args, false); SymbolSet.(sst.args, true)]
    vectorsets = [SymbolSet.(vs.args, false); SymbolSet.(vst.args, true)]

    scname = Symbol(string(instancename) * "ScalarConstraints")
    vcname = Symbol(string(instancename) * "VectorConstraints")

    scalarfuns = [SymbolFun.(sf.args, false, scname); SymbolFun.(sft.args, true, scname)]
    vectorfuns = [SymbolFun.(vf.args, false, vcname); SymbolFun.(vft.args, true, vcname)]
    funs = [scalarfuns; vectorfuns]

    scalarconstraints = :(struct $scname{T, F<:MathOptInterface.AbstractScalarFunction} <: MathOptInterfaceUtilities.Constraints{F}; end)
    vectorconstraints = :(struct $vcname{T, F<:MathOptInterface.AbstractVectorFunction} <: MathOptInterfaceUtilities.Constraints{F}; end)
    for (c, ss) in ((scalarconstraints, scalarsets), (vectorconstraints, vectorsets))
        for s in ss
            field = _field(s)
            push!(c.args[3].args, :($field::Vector{$(_getC(s))}))
        end
    end

    instancedef = quote
        mutable struct $instancename{T} <: MathOptInterfaceUtilities.AbstractInstance{T}
            sense::MathOptInterface.OptimizationSense
            objective::Union{MOI.SingleVariable, MOI.ScalarAffineFunction{T}, MOI.ScalarQuadraticFunction{T}}
            nvars::UInt64
            varnames::Dict{UInt64, String}
            namesvar::Dict{String, MOI.VariableReference}
            nconstrs::UInt64
            connames::Dict{UInt64, String}
            namescon::Dict{String, MOI.ConstraintReference}
            constrmap::Vector{Int} # Constraint Reference value ci -> index in array in Constraints
        end
    end
    for f in funs
        cname = f.cname
        field = _field(f)
        push!(instancedef.args[2].args[3].args, :($field::$cname{T, $(_getC(f))}))
    end

    code = quote
        function MathOptInterfaceUtilities.broadcastcall(f::Function, m::$instancename)
            $(Expr(:block, _broadcastfield.(:(MathOptInterfaceUtilities.broadcastcall), funs)...))
        end
        function MathOptInterfaceUtilities.broadcastvcat(f::Function, m::$instancename)
            vcat($(_broadcastfield.(:(MathOptInterfaceUtilities.broadcastvcat), funs)...))
        end
    end
    for (cname, sets) in ((scname, scalarsets), (vcname, vectorsets))
        code = quote
            $code
            function MathOptInterfaceUtilities.broadcastcall(f::Function, m::$cname)
                $(Expr(:block, _callfield.(:f, sets)...))
            end
            function MathOptInterfaceUtilities.broadcastvcat(f::Function, m::$cname)
                vcat($(_callfield.(:f, sets)...))
            end
        end
    end

    for (func, T) in ((:_addconstraint!, CR), (:_modifyconstraint!, CR), (:_delete!, CR), (:_getfunction, CR), (:_getset, CR), (:_getnoc, MathOptInterface.NumberOfConstraints))
        funct = _mod(MathOptInterfaceUtilities, func)
        for (c, ss) in ((scname, scalarsets), (vcname, vectorsets))
            for s in ss
                set = _set(s)
                field = _field(s)
                code = quote
                    $code
                    $funct{F}(m::$c, cr::$T{F, <:$set}, args...) = $funct(m.$field, cr, args...)
                end
            end
        end

        for f in funs
            fun = _fun(f)
            field = _field(f)
            code = quote
                $code
                $funct(m::$instancename, cr::$T{<:$fun}, args...) = $funct(m.$field, cr, args...)
            end
        end
    end

    return esc(quote
        $scalarconstraints
        function $scname{T, F}() where {T, F}
            $scname{T, F}($(_getCV.(scalarsets)...))
        end

        $vectorconstraints
        function $vcname{T, F}() where {T, F}
            $vcname{T, F}($(_getCV.(vectorsets)...))
        end

        $instancedef
        function $instancename{T}() where T
            $instancename{T}(MathOptInterface.FeasibilitySense, MathOptInterfaceUtilities.SAF{T}(MathOptInterface.VariableReference[], T[], zero(T)),
                   0, Dict{UInt64, String}(), Dict{String, MOI.VariableReference}(),
                   0, Dict{UInt64, String}(), Dict{String, MOI.ConstraintReference}(), Int[],
                   $(_getCV.(funs)...))
        end

        $code

    end)
end
