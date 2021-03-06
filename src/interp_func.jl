struct LinearInterpolationData{uType,tType} <: AbstractDiffEqInterpolation
  timeseries::uType
  ts::tType
end

DiffEqBase.interp_summary(::LinearInterpolationData) = "1st order linear"
(interp::LinearInterpolationData)(tvals,idxs,deriv) = sde_interpolation(tvals,interp,idxs,deriv)
(interp::LinearInterpolationData)(val,tvals,idxs,deriv) = sde_interpolation!(val,tvals,interp,idxs,deriv)
