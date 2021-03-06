#=
@inline function perform_step!(integrator,cache::SRA1ConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  gpdt = integrator.g(t+dt,uprev)
  chi2 = @. (W.dW + W.dZ/sqrt(3))/2 #I_(1,0)/h
  k₁ = @. dt*integrator.f(t,uprev)
  k₂ = @. dt*integrator.f(t+3dt/4,uprev+3k₁/4 + 3chi2*integrator.g(t+dt,uprev)/2)
  E₁ = @. k₁ + k₂
  E₂ = @. chi2.*(integrator.g(t,uprev)-gpdt) #Only for additive!

  if integrator.opts.adaptive
    u = @. uprev + k₁/3 + 2k₂/3 + E₂ + W.dW*gpdt
    tmp = @. @muladd(integrator.opts.delta*E₁+E₂)./@muladd(integrator.opts.abstol + max.(abs.(uprev),abs.(u))*integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(tmp)
  else
    u = @. uprev + k₁/3 + 2k₂/3 + E₂ + W.dW*gpdt
  end
  @pack integrator = t,dt,u
end
=#

@inline function perform_step!(integrator,cache::SRA1ConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  gpdt = integrator.g(t+dt,uprev)
  chi2 = (W.dW + W.dZ/sqrt(3))/2 #I_(1,0)/h
  k₁ = dt*integrator.f(t,uprev)
  k₂ = dt*integrator.f(t+3dt/4,uprev+3k₁/4 + 3chi2*integrator.g(t+dt,uprev)/2)
  E₁ = k₁ + k₂
  E₂ = chi2.*(integrator.g(t,uprev)-gpdt) #Only for additive!

  if integrator.opts.adaptive
    u = uprev + k₁/3 + 2k₂/3 + E₂ + W.dW*gpdt
    integrator.EEst = abs(@muladd(integrator.opts.delta*E₁+E₂)./@muladd(integrator.opts.abstol + max.(abs.(uprev),abs.(u))*integrator.opts.reltol))
  else
    u = uprev + k₁/3 + 2k₂/3 + E₂ + W.dW*gpdt
  end
  @pack integrator = t,dt,u
end

#=
@inline function perform_step!(integrator,cache::SRA1Cache,f=integrator.f)
  @unpack chi2,tmp1,E₁,E₂,gt,k₁,k₂,gpdt,tmp = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.g(t,uprev,gt)
  integrator.g(t+dt,uprev,gpdt)
  integrator.f(t,uprev,k₁); k₁*=dt
  @. chi2 = (W.dW + W.dZ/sqrt(3))/2 #I_(1,0)/h
  @. tmp1 = uprev+3k₁/4 + 3chi2*gpdt/2

  integrator.f(t+3dt/4,tmp1,k₂); k₂*=dt

  @. E₁ = k₁ + k₂
  @. E₂ = chi2*(gt-gpdt) #Only for additive!

  @. u = uprev + k₁/3 + 2k₂/3 + E₂ + W.dW*gpdt

  if integrator.opts.adaptive
    @. tmp = @muladd(integrator.opts.delta*E₁+E₂)/@muladd(integrator.opts.abstol + max(abs(uprev),abs(u))*integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end
=#

@inline function perform_step!(integrator,cache::SRA1Cache,f=integrator.f)
  @unpack chi2,tmp1,E₁,E₂,gt,k₁,k₂,gpdt,tmp = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.g(t,uprev,gt)
  integrator.g(t+dt,uprev,gpdt)
  integrator.f(t,uprev,k₁); k₁*=dt
  for i in eachindex(u)
    @inbounds chi2[i] = (W.dW[i] + W.dZ[i]/sqrt(3))/2 #I_(1,0)/h
    @inbounds tmp1[i] = uprev[i]+3k₁[i]/4 + 3chi2[i]*gpdt[i]/2
  end

  integrator.f(t+3dt/4,tmp1,k₂); k₂*=dt

  for i in eachindex(u)
    @inbounds E₁[i] = k₁[i] + k₂[i]
    @inbounds E₂[i] = chi2[i]*(gt[i]-gpdt[i]) #Only for additive!
  end

  for i in eachindex(u)
    @inbounds u[i] = uprev[i] + k₁[i]/3 + 2k₂[i]/3 + E₂[i] + W.dW[i]*gpdt[i]
  end

  if integrator.opts.adaptive
    @tight_loop_macros for (i,atol,rtol,δ) in zip(eachindex(u),Iterators.cycle(integrator.opts.abstol),
						  Iterators.cycle(integrator.opts.reltol),Iterators.cycle(integrator.opts.delta))
      @inbounds tmp[i] = @muladd(δ*E₁[i]+E₂[i])/@muladd(atol + max(abs(uprev[i]),abs(u[i]))*rtol)
    end
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end

#=
@inline function perform_step!(integrator,cache::SRACache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  @unpack H0,A0temp,B0temp,ftmp,gtmp,chi2,atemp,btemp,E₁,E₁temp,E₂,tmp = cache
  @unpack c₀,c₁,A₀,B₀,α,β₁,β₂,stages = cache.tab
  @. chi2 = .5*(W.dW + W.dZ/sqrt(3)) #I_(1,0)/h
  for i in 1:stages
    fill!(H0[i],zero(eltype(integrator.u)))
  end
  for i = 1:stages
    fill!(A0temp,zero(eltype(integrator.u)))
    fill!(B0temp,zero(eltype(integrator.u)))
    for j = 1:i-1
      integrator.f(@muladd(t + c₀[j]*dt),H0[j],ftmp)
      integrator.g(@muladd(t + c₁[j]*dt),H0[j],gtmp)
      @. A0temp = @muladd A0temp + A₀[j,i]*ftmp
      @. B0temp = @muladd B0temp + B₀[j,i]*gtmp
    end
    @. H0[i] = @muladd uprev + A0temp*dt + B0temp*chi2
  end
  fill!(atemp ,zero(eltype(integrator.u)))
  fill!(btemp ,zero(eltype(integrator.u)))
  fill!(E₂    ,zero(eltype(integrator.u)))
  fill!(E₁temp,zero(eltype(integrator.u)))

  for i = 1:stages
    integrator.f(@muladd(t+c₀[i]*dt),H0[i],ftmp)
    integrator.g(@muladd(t+c₁[i]*dt),H0[i],gtmp)
    @. atemp  =  @muladd atemp  + α[i]*ftmp
    @. btemp  =  @muladd btemp  + (β₁[i]*W.dW)*gtmp
    @. E₂     =  @muladd E₂     + (β₂[i]*chi2)*gtmp
    @. E₁temp =  E₁temp +  ftmp
  end
  @. E₁ = dt*E₁temp
  @. u = @muladd uprev + dt*atemp + btemp + E₂

  if integrator.opts.adaptive
    @. tmp = (integrator.opts.delta*E₁+E₂)/(integrator.opts.abstol + max(abs(uprev),abs(u))*integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end
=#

@inline function perform_step!(integrator,cache::SRACache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  @unpack H0,A0temp,B0temp,ftmp,gtmp,chi2,atemp,btemp,E₁,E₁temp,E₂,tmp = cache
  @unpack c₀,c₁,A₀,B₀,α,β₁,β₂,stages = cache.tab
  for i in eachindex(u)
    @inbounds chi2[i] = .5*(W.dW[i] + W.dZ[i]/sqrt(3)) #I_(1,0)/h
  end
  for i in 1:stages
    fill!(H0[i],zero(eltype(integrator.u)))
  end
  for i = 1:stages
    fill!(A0temp,zero(eltype(integrator.u)))
    fill!(B0temp,zero(eltype(integrator.u)))
    for j = 1:i-1
      integrator.f(@muladd(t + c₀[j]*dt),H0[j],ftmp)
      integrator.g(@muladd(t + c₁[j]*dt),H0[j],gtmp)
      @tight_loop_macros for k in eachindex(u)
        @inbounds A0temp[k] = @muladd A0temp[k] + A₀[j,i]*ftmp[k]
        @inbounds B0temp[k] = @muladd B0temp[k] + B₀[j,i]*gtmp[k]
      end
    end
    @tight_loop_macros for j in eachindex(u)
      @inbounds H0[i][j] = @muladd uprev[j] + A0temp[j]*dt + B0temp[j]*chi2[j]
    end
  end
  fill!(atemp ,zero(eltype(integrator.u)))
  fill!(btemp ,zero(eltype(integrator.u)))
  fill!(E₂    ,zero(eltype(integrator.u)))
  fill!(E₁temp,zero(eltype(integrator.u)))

  for i = 1:stages
    integrator.f(@muladd(t+c₀[i]*dt),H0[i],ftmp)
    integrator.g(@muladd(t+c₁[i]*dt),H0[i],gtmp)
    @tight_loop_macros for j in eachindex(u)
      @inbounds atemp[j]  =  @muladd atemp[j]  + α[i]*ftmp[j]
      @inbounds btemp[j]  =  @muladd btemp[j]  + (β₁[i]*W.dW[j])*gtmp[j]
      @inbounds E₂[j]     =  @muladd E₂[j]     + (β₂[i]*chi2[j])*gtmp[j]
      @inbounds E₁temp[j] =  E₁temp[j] +  ftmp[j]
    end
  end
  @tight_loop_macros for i in eachindex(u)
    @inbounds E₁[i] = dt*E₁temp[i]
  end

  @tight_loop_macros for i in eachindex(u)
    @inbounds u[i] = @muladd uprev[i] + dt*atemp[i] + btemp[i] + E₂[i]
  end

  if integrator.opts.adaptive
    @tight_loop_macros for (i,atol,rtol,δ) in zip(eachindex(u),Iterators.cycle(integrator.opts.abstol),
						  Iterators.cycle(integrator.opts.reltol),Iterators.cycle(integrator.opts.delta))
      @inbounds tmp[i] = @muladd(δ*E₁[i]+E₂[i])/@muladd(atol + max(abs(uprev[i]),abs(u[i]))*rtol)
    end
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end

#=
@inline function perform_step!(integrator,cache::SRAConstantCache,f=integrator.f)
  @unpack c₀,c₁,A₀,B₀,α,β₁,β₂,stages,H0 = cache
  @unpack t,dt,uprev,u,W = integrator
  chi2 = @. .5*(W.dW + W.dZ/sqrt(3)) #I_(1,0)/h
  H0 .= zero(zero(u))
  for i = 1:stages
    A0temp = zero(u)
    B0temp = zero(u)
    for j = 1:i-1
      A0temp = @muladd A0temp .+ A₀[j,i].*integrator.f(@muladd(t .+ c₀[j].*dt),H0[j])
      B0temp = @muladd B0temp .+ B₀[j,i].*integrator.g(@muladd(t .+ c₁[j].*dt),H0[j]) #H0[..,i] argument ignored
    end
    H0[i] = @. uprev + A0temp*dt + B0temp.*chi2
  end

  atemp = zero(u)
  btemp = zero(u)
  E₂    = zero(u)
  E₁temp= zero(u)

  for i = 1:stages
    ftemp = integrator.f(t+c₀[i]*dt,H0[i])
    E₁temp =  @. E₁temp +  ftemp
    atemp  =  @. @muladd atemp  + α[i]*ftemp
    btemp  =  @muladd btemp  .+ (β₁[i].*W.dW ).* integrator.g(@muladd(t.+c₁[i]*dt),H0[i]) #H0[i] argument ignored
    E₂     =  @muladd E₂     .+ (β₂[i].*chi2) .* integrator.g(@muladd(t.+c₁[i]*dt),H0[i]) #H0[i] argument ignored
  end

  u = @. @muladd uprev + dt*atemp + btemp + E₂

  if integrator.opts.adaptive
    E₁ = @. dt*E₁temp
    tmp = @. @muladd(integrator.opts.delta*E₁+E₂)/@muladd(integrator.opts.abstol + max.(abs(uprev),abs(u))*integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end
=#

@inline function perform_step!(integrator,cache::SRAConstantCache,f=integrator.f)
  @unpack c₀,c₁,A₀,B₀,α,β₁,β₂,stages,H0 = cache
  @unpack t,dt,uprev,u,W = integrator
  chi2 = .5*(W.dW + W.dZ/sqrt(3)) #I_(1,0)/h
  H0[:]=zeros(stages)
  for i = 1:stages
    A0temp = zero(u)
    B0temp = zero(u)
    for j = 1:i-1
      A0temp = @muladd A0temp + A₀[j,i]*integrator.f(@muladd(t + c₀[j]*dt),H0[j])
      B0temp = @muladd B0temp + B₀[j,i]*integrator.g(@muladd(t + c₁[j]*dt),H0[j]) #H0[..,i] argument ignored
    end
    H0[i] = uprev + A0temp*dt + B0temp.*chi2
  end

  atemp = zero(u)
  btemp = zero(u)
  E₂    = zero(u)
  E₁temp= zero(u)

  for i = 1:stages
    ftemp = integrator.f(t+c₀[i]*dt,H0[i])
    E₁temp =  E₁temp +  ftemp
    atemp  =  @muladd atemp  + α[i]*ftemp
    btemp  =  @muladd btemp  + (β₁[i]*W.dW ).* integrator.g(@muladd(t+c₁[i]*dt),H0[i]) #H0[i] argument ignored
    E₂     =  @muladd E₂     + (β₂[i]*chi2).*integrator.g(@muladd(t+c₁[i]*dt),H0[i]) #H0[i] argument ignored
  end

  u = @muladd uprev + dt*atemp + btemp + E₂

  if integrator.opts.adaptive
    E₁ = dt*E₁temp
    integrator.EEst = integrator.opts.internalnorm(@muladd(integrator.opts.delta*E₁+E₂)./@muladd(integrator.opts.abstol + max.(abs.(uprev),abs.(u))*integrator.opts.reltol))
  end
  @pack integrator = t,dt,u
end
