
# An Int-valued attribute
struct MockInstanceAttribute <: MOI.AbstractInstanceAttribute
end

# An Int-valued attribute
struct MockVariableAttribute <: MOI.AbstractVariableAttribute
end

# An Int-valued attribute
struct MockConstraintAttribute <: MOI.AbstractConstraintAttribute
end

# A mock solver instance used for testing.
mutable struct MockSolverInstance <: MOI.AbstractSolverInstance
    instance::MOI.AbstractStandaloneInstance
    attribute::Int # MockInstanceAttribute
    varattribute::Dict{MOI.VariableIndex,Int} # MockVariableAttribute
    conattribute::Dict{MOI.ConstraintIndex,Int} # MockConstraintAttribute
    solved::Bool
    terminationstatus::MOI.TerminationStatusCode
    resultcount::Int
    objectivevalue::Float64
    primalstatus::MOI.ResultStatusCode
    varprimal::Dict{MOI.VariableIndex,Float64}
    # TODO: constraint primal
    # TODO: dual status and dual result
end

MockSolverInstance(instance::MOI.AbstractStandaloneInstance) =
    MockSolverInstance(instance,
                       0,
                       Dict{MOI.VariableIndex,Int}(),
                       Dict{MOI.ConstraintIndex,Int}(),
                       false,
                       MOI.Success,
                       0,
                       NaN,
                       MOI.UnknownResultStatus,
                       Dict{MOI.VariableIndex,Float64}())

MOI.addvariable!(mock::MockSolverInstance) = MOI.addvariable!(mock.instance)
MOI.addvariables!(mock::MockSolverInstance, n::Int) = MOI.addvariables!(mock.instance, n)
MOI.addconstraint!(mock::MockSolverInstance, F, S) = MOI.addconstraint!(mock.instance, F, S)
MOI.optimize!(mock::MockSolverInstance) = (mock.solved = true)

MOI.canset(mock::MockSolverInstance, ::Union{MOI.ResultCount,MOI.TerminationStatus,MOI.ObjectiveValue,MOI.PrimalStatus,MockInstanceAttribute}) = true
MOI.canset(mock::MockSolverInstance, ::Union{MOI.VariablePrimal,MockVariableAttribute}, ::MOI.VariableIndex) = true
MOI.canset(mock::MockSolverInstance, ::Union{MOI.VariablePrimal,MockVariableAttribute}, ::Vector{MOI.VariableIndex}) = true
MOI.canset(mock::MockSolverInstance, ::MockConstraintAttribute, ::MOI.ConstraintIndex) = true
MOI.canset(mock::MockSolverInstance, ::MockConstraintAttribute, ::Vector{<:MOI.ConstraintIndex}) = true

MOI.set!(mock::MockSolverInstance, ::MOI.ResultCount, value::Integer) = (mock.resultcount = value)
MOI.set!(mock::MockSolverInstance, ::MOI.TerminationStatus, value::MOI.TerminationStatusCode) = (mock.terminationstatus = value)
MOI.set!(mock::MockSolverInstance, ::MOI.ObjectiveValue, value::Real) = (mock.objectivevalue = value)
MOI.set!(mock::MockSolverInstance, ::MOI.PrimalStatus, value::MOI.ResultStatusCode) = (mock.primalstatus = value)
MOI.set!(mock::MockSolverInstance, ::MockInstanceAttribute, value::Integer) = (mock.attribute = value)

MOI.set!(mock::MockSolverInstance, ::MOI.VariablePrimal, idx::MOI.VariableIndex, value) = (mock.varprimal[idx] = value)
MOI.set!(mock::MockSolverInstance, ::MockVariableAttribute, idx::MOI.VariableIndex, value) = (mock.varattribute[idx] = value)
MOI.set!(mock::MockSolverInstance, ::MockConstraintAttribute, idx::MOI.ConstraintIndex, value) = (mock.conattribute[idx] = value)
function MOI.set!(mock::MockSolverInstance, ::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex}, value)
    for (i,v) in zip(idx, value)
        mock.varprimal[i] = v
    end
end
function MOI.set!(mock::MockSolverInstance, ::MockVariableAttribute, idx::Vector{MOI.VariableIndex}, value)
    for (i,v) in zip(idx, value)
        mock.varattribute[i] = v
    end
end
function MOI.set!(mock::MockSolverInstance, ::MockConstraintAttribute, idx::Vector{<:MOI.ConstraintIndex}, value)
    for (i,v) in zip(idx, value)
        mock.conattribute[i] = v
    end
end


MOI.canget(mock::MockSolverInstance, ::MOI.ResultCount) = mock.solved
MOI.canget(mock::MockSolverInstance, ::MOI.TerminationStatus) = mock.solved
MOI.canget(mock::MockSolverInstance, ::MOI.ObjectiveValue) = mock.solved # TODO: may want to simulate false
MOI.canget(mock::MockSolverInstance, ::MOI.PrimalStatus) = mock.solved && (mock.resultcount > 0)
MOI.canget(mock::MockSolverInstance, ::MockInstanceAttribute) = true

# We assume that a full result is loaded if resultcount > 0
MOI.canget(mock::MockSolverInstance, ::MOI.VariablePrimal, ::MOI.VariableIndex) = (mock.resultcount > 0)
MOI.canget(mock::MockSolverInstance, ::MOI.VariablePrimal, ::Vector{MOI.VariableIndex}) = (mock.resultcount > 0)

MOI.canget(mock::MockSolverInstance, ::MockVariableAttribute, idx::MOI.VariableIndex) = haskey(mock.varattribute, idx)
MOI.canget(mock::MockSolverInstance, ::MockVariableAttribute, idx::Vector{MOI.VariableIndex}) = all(haskey.(mock.varattribute, idx))
MOI.canget(mock::MockSolverInstance, ::MockConstraintAttribute, idx::MOI.ConstraintIndex) = haskey(mock.conattribute, idx)
MOI.canget(mock::MockSolverInstance, ::MockConstraintAttribute, idx::Vector{<:MOI.ConstraintIndex}) = all(haskey.(mock.conattribute, idx))

MOI.get(mock::MockSolverInstance, ::MOI.ResultCount) = mock.resultcount
MOI.get(mock::MockSolverInstance, ::MOI.TerminationStatus) = mock.terminationstatus
MOI.get(mock::MockSolverInstance, ::MOI.ObjectiveValue) = mock.objectivevalue
MOI.get(mock::MockSolverInstance, ::MOI.PrimalStatus) = mock.primalstatus
MOI.get(mock::MockSolverInstance, ::MockInstanceAttribute) = mock.attribute

MOI.get(mock::MockSolverInstance, ::MockVariableAttribute, idx::MOI.VariableIndex) = mock.varattribute[idx]
MOI.get(mock::MockSolverInstance, ::MockVariableAttribute, idx::Vector{MOI.VariableIndex}) = getindex.(mock.varattribute, idx)
MOI.get(mock::MockSolverInstance, ::MOI.VariablePrimal, idx::MOI.VariableIndex) = mock.varprimal[idx]
MOI.get(mock::MockSolverInstance, ::MOI.VariablePrimal, idx::Vector{MOI.VariableIndex}) = getindex.(mock.varprimal, idx)
MOI.get(mock::MockSolverInstance, ::MockConstraintAttribute, idx::MOI.ConstraintIndex) = mock.conattribute[idx]
MOI.get(mock::MockSolverInstance, ::MockConstraintAttribute, idx::Vector{<:MOI.ConstraintIndex}) = getindex.(mock.conattribute, idx)