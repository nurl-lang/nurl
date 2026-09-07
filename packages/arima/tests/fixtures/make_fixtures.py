#!/usr/bin/env python
"""Regenerate statsmodels_cases.json: deterministic series and statsmodels'
exact-ML fits, forecasts and standard errors, the oracle for tests/arima_test.nu.
Run with the reference venv (needs statsmodels)."""
import json, time, warnings, numpy as np
warnings.filterwarnings("ignore")
from statsmodels.tsa.arima.model import ARIMA
from statsmodels.tsa.arima_process import ArmaProcess
cases = {}
def fit(name, y, order, sorder=(0,0,0,0), trend='n', h=12):
    t0 = time.time()
    m = ARIMA(y, order=order, seasonal_order=sorder, trend=trend).fit()
    dt = time.time() - t0
    fc = m.get_forecast(h)
    params = {k: float(v) for k, v in zip(m.model.param_names, m.params)}
    cases[name] = dict(order=list(order), seasonal_order=list(sorder), trend=trend, y=[float(v) for v in y],
        params=params, llf=float(m.llf), aic=float(m.aic),
        forecast=[float(v) for v in fc.predicted_mean], forecast_se=[float(v) for v in fc.se_mean], fit_seconds=dt)
np.random.seed(7)
y = ArmaProcess(np.r_[1, -0.7], np.r_[1]).generate_sample(500, burnin=200); fit("ar1", y, (1,0,0))
y = ArmaProcess(np.r_[1], np.r_[1, 0.5]).generate_sample(500, burnin=200); fit("ma1", y, (0,0,1))
y = ArmaProcess(np.r_[1, -0.5, 0.25], np.r_[1, 0.4]).generate_sample(800, burnin=200); fit("arma21", y, (2,0,1))
y = 3.0 + ArmaProcess(np.r_[1, -0.6], np.r_[1, 0.3]).generate_sample(600, burnin=200); fit("arma11_mean", y, (1,0,1), trend='c')
y = np.cumsum(ArmaProcess(np.r_[1, -0.5], np.r_[1, 0.4]).generate_sample(600, burnin=200)); fit("arima111", y, (1,1,1))
air = [112,118,132,129,121,135,148,148,136,119,104,118,115,126,141,135,125,149,170,170,158,133,114,140,145,150,178,163,172,178,199,199,184,162,146,166,171,180,193,181,183,218,230,242,209,191,172,194,196,196,236,235,229,243,264,272,237,211,180,201,204,188,235,227,234,264,302,293,259,229,203,229,242,233,267,269,270,315,364,347,312,274,237,278,284,277,317,313,318,374,413,405,355,306,271,306,315,301,356,348,355,422,465,467,404,347,305,336,340,318,362,348,363,435,491,505,404,359,310,337,360,342,406,396,420,472,548,559,463,407,362,405,417,391,419,461,472,535,622,606,508,461,390,432]
fit("airline", np.log(np.array(air, dtype=float)), (0,1,1), (0,1,1,12))
ys = np.zeros(700)
for t in range(700): ys[t] = 0.5*(ys[t-1] if t>0 else 0) + 0.6*(ys[t-12] if t>=12 else 0) - 0.3*(ys[t-13] if t>=13 else 0) + np.random.standard_normal()
fit("sar", ys[100:], (1,0,0), (1,0,0,12))
yb = ArmaProcess(np.r_[1, -0.5, 0.25], np.r_[1, 0.4]).generate_sample(10000, burnin=200); fit("arma21_big", yb, (2,0,1), h=5)
json.dump(cases, open("statsmodels_cases.json", "w"))
print("written", len(cases), "cases")
