using StochasticDiffEq, DiffEqDevTools, DiffEqBase, DiffEqProblemLibrary, Base.Test
srand(100)
prob = prob_sde_linear
f(t,u) = 2u
prob = SDEProblem{false}(f,prob.f,prob.u0,prob.tspan)
sol = solve(prob,EM(),dt=1//2^(4),saveat = 0.33)

sol.t == [0.0,.33,.33+.33,1]

sol = solve(prob,EM(),dt=1//2^(4),saveat = 0.33,save_start=false)

sol.t == [.33,.33+.33,1]
sol(0.4)

sol = solve(prob,EM(),dt=1//2^(4),saveat = 0.33,save_start=false,save_everystep=true)

@test 0.33 ∈ sol.t
@test 0.66 ∈ sol.t
sol.t != [.33,.33+.33,1]

prob = prob_sde_2Dlinear
f(t,u,du) = prob.f(t,u,du)
prob2 = SDEProblem(f,prob.g,vec(prob.u0),prob.tspan)
srand(200)
sol = solve(prob2,EM(),dt=1//2^(4),saveat = 0.33,save_start=false,save_everystep=true)
srand(200)
sol2= solve(prob2,EM(),dt=1//2^(4),saveat = 0.33,save_start=false,save_everystep=true,save_idxs=1:2:5)

@test sol(0.43)[1:2:5] == sol2(0.43)
