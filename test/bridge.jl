MOIU.@instance NoIntervalLPInstance () (EqualTo, GreaterThan, LessThan) (Zeros, Nonnegatives, Nonpositives) () (SingleVariable,) (ScalarAffineFunction,) (VectorOfVariables,) (VectorAffineFunction,)
MOIU.@bridge SplitInterval MOIU.SplitIntervalBridge () (Interval,) () () () (ScalarAffineFunction,) () ()

@testset "Interval brige" begin
    const instance = SplitInterval{Int}(Instance{Int}())

    x, y = MOI.addvariables!(instance, 2)
    @test MOI.get(instance, MOI.NumberOfVariables()) == 2

    f1 = MOI.ScalarAffineFunction([x], [3], 7)
    c1 = MOI.addconstraint!(instance, f1, MOI.Interval(-1, 1))

    @test MOI.canget(instance, MOI.ListOfConstraints())
    @test MOI.get(instance, MOI.ListOfConstraints()) == [(MOI.ScalarAffineFunction{Int},MOI.Interval{Int})]
    @test MOI.canget(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}())
    @test MOI.get(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}()) == 0
    @test MOI.canget(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}())
    @test MOI.get(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}()) == 1
    @test MOI.canget(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}())
    @test (@inferred MOI.get(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}())) == [c1]

    f2 = MOI.ScalarAffineFunction([x, y], [2, -1], 2)
    c2 = MOI.addconstraint!(instance, f1, MOI.GreaterThan(-2))

    @test MOI.canget(instance, MOI.ListOfConstraints())
    @test MOI.get(instance, MOI.ListOfConstraints()) == [(MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}), (MOI.ScalarAffineFunction{Int},MOI.Interval{Int})]
    @test MOI.canget(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}())
    @test MOI.get(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}()) == 1
    @test MOI.canget(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}())
    @test MOI.get(instance, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}()) == 1
    @test MOI.canget(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}())
    @test (@inferred MOI.get(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Int},MOI.Interval{Int}}())) == [c1]
    @test (@inferred MOI.get(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Int},MOI.GreaterThan{Int}}())) == [c2]
end
