"""Numerical check of the bCCNN explainers (numpy only, no Keras).

Replicates, on a synthetic 20 x 20 triangle:
  * the ccODP fit of R/fit ODP GLM (IWLS), its chain-ladder equivalence,
    score equations, scale property and dispersion estimates;
  * the bCCNN of R/nn_models.R (bccnn_model): forward pass, start property,
    analytic gradients against finite differences, parameter counts,
    Keras loss <-> deviance identity, RMSprop first step;
  * a toy early-stopping run (train half / validation half) and the refit.
Writes results.json and figures/*.png.
"""
import json, math, os
OUTDIR = os.environ.get('OUTDIR', '.')
os.makedirs(OUTDIR + '/figures', exist_ok=True)
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

rng = np.random.default_rng(2026)
n = 20
I = np.arange(1, n + 1)[:, None] * np.ones((1, n), int)   # accident period
J = np.ones((n, 1), int) * np.arange(1, n + 1)[None, :]   # development period
OBS = (I + J <= n + 1)                                     # observed cells
FUT = ~OBS
out = {}

# ---------------------------------------------------------------- data ------
# true structure: ccODP plus an interaction the ccODP cannot represent
c_true = math.log(float(os.environ.get('MU11', '60')))                                   # millions
alpha_true = np.concatenate([[0.0], 0.025 * np.arange(1, n) + rng.normal(0, 0.03, n - 1)])
beta_true = np.concatenate([[0.0], -0.33 * np.arange(1, n) + rng.normal(0, 0.05, n - 1)])
gamma = float(os.environ.get('GAMMA', '0.012'))
inter = gamma * (I - 10.5) * (J - 4.5) * (J <= int(os.environ.get('JCUT', '8')))         # interaction term
log_mu_true = c_true + alpha_true[I - 1] + beta_true[J - 1] + inter
mu_true = np.exp(log_mu_true)
phi_true = float(os.environ.get('PHI', '0.4'))
def odp_draw(m):                                          # Y = phi * Poisson(m / phi)
    return phi_true * rng.poisson(m / phi_true)
y_half1 = odp_draw(mu_true / 2)                           # two independent halves
y_half2 = odp_draw(mu_true / 2)
y_full = y_half1 + y_half2
out["data"] = dict(n=n, c_true=c_true, phi_true=phi_true, gamma=gamma,
                   total_observed=float(y_full[OBS].sum()),
                   true_reserve=float(y_full[FUT].sum()))

# ---------------------------------------------------------------- ccODP -----
def design(cells):
    """treatment contrasts: intercept, origin 2..n, dev 2..n (n_par = 2n - 1)"""
    i = I[cells]; j = J[cells]
    X = np.zeros((cells.sum(), 2 * n - 1))
    X[:, 0] = 1.0
    for r in range(len(i)):
        if i[r] > 1: X[r, i[r] - 1] = 1.0
        if j[r] > 1: X[r, n - 1 + j[r] - 1] = 1.0
    return X

def fit_odp(y, cells=None, tol=1e-10, maxit=100):
    if cells is None: cells = OBS
    X = design(cells); yy = y[cells]
    b = np.zeros(X.shape[1]); b[0] = math.log(max(yy.mean(), 1e-12))
    for it in range(maxit):
        eta = X @ b; mu = np.exp(eta)
        z = eta + (yy - mu) / mu
        W = mu
        XtW = X.T * W
        b_new = np.linalg.solve(XtW @ X, XtW @ z)
        if np.max(np.abs(b_new - b)) < tol * (1 + np.max(np.abs(b))):
            b = b_new; break
        b = b_new
    c0 = b[0]; alpha = np.concatenate([[0.0], b[1:n]]); beta = np.concatenate([[0.0], b[n:]])
    mu = np.exp(c0 + alpha[:, None] + beta[None, :])
    ym = np.where(cells, y, np.nan)
    dev = poisson_deviance(ym, mu)
    n_obs = int(cells.sum()); n_par = 2 * n - 1
    phi_dev = dev / (n_obs - n_par)
    phi_pea = float(np.sum((y[cells] - mu[cells]) ** 2 / mu[cells]) / (n_obs - n_par))
    return dict(c=c0, alpha=alpha, beta=beta, mu=mu, y=np.where(OBS, y, np.nan),
                cells=cells, deviance=dev, phi=phi_dev, phi_pearson=phi_pea,
                n_obs=n_obs, n_par=n_par, iterations=it + 1,
                reserve=float(mu[FUT].sum()), reserve_o=mu.copy() * FUT)

def poisson_deviance(y, mu):
    ok = ~np.isnan(y); y = y[ok]; mu = mu[ok]
    return float(2 * np.sum(mu - y + np.where(y > 0, y * np.log(np.where(y > 0, y, 1) / mu), 0)))

def chain_ladder_reserve(y):
    C = np.cumsum(np.where(OBS, y, 0), axis=1)
    f = np.zeros(n)
    for j in range(1, n):                                  # factor from column j to j+1 (0-based)
        rows = np.arange(n - j)
        f[j] = C[rows, j].sum() / C[rows, j - 1].sum()
    full = C.copy()
    for i in range(n):
        last = n - 1 - i                                   # last observed column of row i
        for j in range(last + 1, n):
            full[i, j] = full[i, j - 1] * f[j]
    latest = C[np.arange(n), n - 1 - np.arange(n)]
    return float((full[:, n - 1] - latest).sum()), f

odp = fit_odp(y_full)
cl_res, cl_f = chain_ladder_reserve(y_full)
score_rows = np.array([np.sum((odp["mu"] - y_full)[i, :][OBS[i, :]]) for i in range(n)])
score_cols = np.array([np.sum((odp["mu"] - y_full)[:, j][OBS[:, j]]) for j in range(n)])
# scale property
u = 1000.0
odp_u = fit_odp(y_full / u)
# cumulative development factors of the ccODP mean square are the same in every row
def cum_dev_factors(mu):
    C = np.cumsum(mu, axis=1)
    return C[:, 1:] / C[:, [0]]
g_odp = cum_dev_factors(odp["mu"])
out["ccodp"] = dict(
    iterations=odp["iterations"], c=odp["c"], deviance=odp["deviance"],
    phi_deviance=odp["phi"], phi_pearson=odp["phi_pearson"], n_obs=odp["n_obs"], n_par=odp["n_par"],
    reserve=odp["reserve"], chain_ladder_reserve=cl_res,
    rel_diff_reserve_vs_cl=abs(odp["reserve"] / cl_res - 1),
    max_abs_row_score=float(np.max(np.abs(score_rows))), max_abs_col_score=float(np.max(np.abs(score_cols))),
    scale_c_shift=odp_u["c"] - odp["c"], scale_log_u=-math.log(u),
    scale_max_abs_diff_alpha=float(np.max(np.abs(odp_u["alpha"] - odp["alpha"]))),
    scale_max_abs_diff_beta=float(np.max(np.abs(odp_u["beta"] - odp["beta"]))),
    scale_reserve_times_u=odp_u["reserve"] * u,
    cum_dev_factor_row_spread=float(np.max(g_odp.max(0) - g_odp.min(0))),
    cl_factors_from_cum_mu=[float(v) for v in (np.cumsum(odp["mu"], 1)[0, 1:] / np.cumsum(odp["mu"], 1)[0, :-1])[:5]],
    cl_factors_data=[float(v) for v in cl_f[1:6]],
    true_reserve=out["data"]["true_reserve"], bias_cl=odp["reserve"] - out["data"]["true_reserve"],
)

# ---------------------------------------------------------------- bCCNN -----
q = (20, 15, 10); p_drop = 0.1
def glorot(fan_in, fan_out, rng):
    lim = math.sqrt(6.0 / (fan_in + fan_out))
    return rng.uniform(-lim, lim, size=(fan_in, fan_out))

def init_params(odp, seed):
    r = np.random.default_rng(seed)
    P = dict(W1=glorot(2, q[0], r), b1=np.zeros(q[0]),
             W2=glorot(q[0], q[1], r), b2=np.zeros(q[1]),
             W3=glorot(q[1], q[2], r), b3=np.zeros(q[2]),
             B=np.zeros(q[2]), w=np.array(1.0), c=np.array(float(odp["c"])))
    return P

def forward(P, alpha, beta, cells, masks=None):
    i = I[cells] - 1; j = J[cells] - 1
    z0 = np.stack([alpha[i], beta[j]], 1)                  # (N, 2)
    cc0 = alpha[i] + beta[j]
    z1 = np.tanh(P["b1"] + z0 @ P["W1"]);  z1d = z1 if masks is None else z1 * masks[0]
    z2 = np.tanh(P["b2"] + z1d @ P["W2"]); z2d = z2 if masks is None else z2 * masks[1]
    z3 = np.tanh(P["b3"] + z2d @ P["W3"]); z3d = z3 if masks is None else z3 * masks[2]
    a = P["w"] * cc0 + P["c"] + z3d @ P["B"]
    mu = np.exp(a)
    return dict(z0=z0, cc0=cc0, z1=z1, z1d=z1d, z2=z2, z2d=z2d, z3=z3, z3d=z3d, a=a, mu=mu)

def backward(P, F, delta, masks=None):
    """delta = dLoss/da per cell. Returns gradient dict."""
    G = {}
    G["c"] = delta.sum(); G["w"] = (delta * F["cc0"]).sum(); G["B"] = F["z3d"].T @ delta
    g3 = np.outer(delta, P["B"])
    if masks is not None: g3 = g3 * masks[2]
    g3 = g3 * (1 - F["z3"] ** 2)
    G["W3"] = F["z2d"].T @ g3; G["b3"] = g3.sum(0)
    g2 = g3 @ P["W3"].T
    if masks is not None: g2 = g2 * masks[1]
    g2 = g2 * (1 - F["z2"] ** 2)
    G["W2"] = F["z1d"].T @ g2; G["b2"] = g2.sum(0)
    g1 = g2 @ P["W2"].T
    if masks is not None: g1 = g1 * masks[0]
    g1 = g1 * (1 - F["z1"] ** 2)
    G["W1"] = F["z0"].T @ g1; G["b1"] = g1.sum(0)
    return G

def deviance_on(P, odp, y, cells):
    F = forward(P, odp["alpha"], odp["beta"], cells)
    yy = y[cells]
    return float(2 * np.sum(F["mu"] - yy + np.where(yy > 0, yy * np.log(np.where(yy > 0, yy, 1) / F["mu"]), 0)))

def mu_square(P, odp):
    F = forward(P, odp["alpha"], odp["beta"], np.ones((n, n), bool))
    return F["mu"].reshape(n, n)

n_par_hidden = (2 + 1) * q[0] + (q[0] + 1) * q[1] + (q[1] + 1) * q[2]
n_par_out = (1 + q[2]) + 1
P0 = init_params(odp, seed=2026)
mu0 = mu_square(P0, odp)
out["bccnn"] = dict(
    hidden_params=n_par_hidden, output_params=n_par_out, trainable=n_par_hidden + n_par_out,
    embedding_params=2 * n, total=n_par_hidden + n_par_out + 2 * n,
    start_max_rel_diff_mu=float(np.max(np.abs(mu0 / odp["mu"] - 1))),
    start_reserve=float(mu0[FUT].sum()), odp_reserve=odp["reserve"],
    start_deviance=deviance_on(P0, odp, y_full, OBS), odp_deviance=odp["deviance"],
)

# gradients of the deviance at the start and at a random point, vs finite differences
def grad_dev(P, odp, y, cells):
    F = forward(P, odp["alpha"], odp["beta"], cells)
    delta = 2 * (F["mu"] - y[cells])
    return backward(P, F, delta)

def fd_check(P, odp, y, cells, h=1e-6, rng=None):
    G = grad_dev(P, odp, y, cells)
    res = {}
    for k in P:
        arr = np.atleast_1d(P[k]).astype(float)
        idx = [tuple(x) for x in np.argwhere(np.ones_like(arr, dtype=bool))]
        if rng is not None and len(idx) > 12:
            idx = [idx[t] for t in rng.choice(len(idx), 12, replace=False)]
        max_abs_err = 0.0; max_rel_err = 0.0; max_g = 0.0
        for ix in idx:
            Pp = {kk: np.array(v, dtype=float) for kk, v in P.items()}
            Pm = {kk: np.array(v, dtype=float) for kk, v in P.items()}
            ap = np.atleast_1d(Pp[k]); am = np.atleast_1d(Pm[k])
            ap[ix] += h; am[ix] -= h
            Pp[k] = ap.reshape(np.shape(P[k])); Pm[k] = am.reshape(np.shape(P[k]))
            fd = (deviance_on(Pp, odp, y, cells) - deviance_on(Pm, odp, y, cells)) / (2 * h)
            an = np.atleast_1d(G[k])[ix]
            max_abs_err = max(max_abs_err, abs(fd - an)); max_g = max(max_g, abs(an))
            max_rel_err = max(max_rel_err, abs(fd - an) / max(1e-8, abs(an)) if abs(an) > 1e-6 else abs(fd - an))
        res[k] = dict(max_abs_grad=float(np.max(np.abs(G[k]))), max_abs_err=max_abs_err, max_rel_err=max_rel_err)
    return res, G

fd_start, G0 = fd_check(P0, odp, y_full, OBS, rng=np.random.default_rng(1))
out["gradient_at_start"] = {k: dict(max_abs_grad=v["max_abs_grad"], fd_max_abs_err=v["max_abs_err"]) for k, v in fd_start.items()}
P1 = {k: np.array(v, dtype=float) for k, v in P0.items()}
P1["B"] = np.random.default_rng(7).normal(0, 0.3, q[2]); P1["w"] = np.array(0.9); P1["c"] = P0["c"] + 0.2
fd_rand, G1 = fd_check(P1, odp, y_full, OBS, rng=np.random.default_rng(2))
out["gradient_at_random_point"] = {k: dict(max_abs_grad=v["max_abs_grad"], fd_max_rel_err=v["max_rel_err"]) for k, v in fd_rand.items()}

# Keras "poisson" loss <-> deviance identity
def keras_poisson(mu, y):
    return float(np.mean(mu - y * np.log(mu + 1e-7)))           # Keras adds epsilon inside the log
F0 = forward(P0, odp["alpha"], odp["beta"], OBS)
yy = y_full[OBS]; N = yy.size
L_keras = float(np.mean(F0["mu"] - yy * np.log(F0["mu"])))
dev_from_keras = 2 * N * L_keras + 2 * np.sum(np.where(yy > 0, yy * np.log(np.where(yy > 0, yy, 1)), 0) - yy)
out["keras_identity"] = dict(N=int(N), L_keras=L_keras, deviance_from_identity=float(dev_from_keras),
                             deviance_direct=deviance_on(P0, odp, y_full, OBS),
                             keras_epsilon_effect=abs(keras_poisson(F0["mu"], yy) - L_keras))

# ---------------------------------------------------------------- RMSprop ---
lr, rho, eps = 0.001, 0.9, 1e-7
def rmsprop_run(P, odp, y, cells, steps, seed, dropout=True, track=None):
    """full batch; Keras loss = mean(mu - y log mu); Keras RMSprop; inverted dropout.
    Records, after every step, the deviance without dropout on the training cells
    and on each matrix in `track` (NA outside), plus Keras's reported loss as a
    deviance (train_dropout). Epoch 0 = start."""
    r = np.random.default_rng(seed)
    P = {k: np.array(v, dtype=float) for k, v in P.items()}
    V = {k: np.zeros_like(np.atleast_1d(v)) for k, v in P.items()}
    yy = y[cells]; N = yy.size
    hist = []; mu_path = []
    def record(step, loss):
        musq = mu_square(P, odp); mu_path.append(musq)
        row = dict(epoch=step, train=poisson_deviance(np.where(cells, y, np.nan), musq),
                   train_dropout=(2 * N * loss + 2 * np.sum(np.where(yy > 0, yy * np.log(np.where(yy > 0, yy, 1)), 0) - yy)) if loss is not None else np.nan)
        for name, t in (track or {}).items():
            row[name] = poisson_deviance(t, musq); row[name + "_pred"] = float(np.nansum(np.where(~np.isnan(t), musq, 0)))
        hist.append(row)
    record(0, None)
    first_update = None
    for s in range(1, steps + 1):
        masks = None
        if dropout:
            masks = [r.binomial(1, 1 - p_drop, size=(N, qq)) / (1 - p_drop) for qq in q]
        F = forward(P, odp["alpha"], odp["beta"], cells, masks)
        loss = float(np.mean(F["mu"] - yy * np.log(F["mu"])))   # computed before the update
        delta = (F["mu"] - yy) / N
        G = backward(P, F, delta, masks)
        upd = {}
        for k in P:
            g = np.atleast_1d(G[k]).astype(float)
            V[k] = rho * V[k] + (1 - rho) * g * g
            step_k = lr * g / (np.sqrt(V[k]) + eps)
            upd[k] = step_k
            P[k] = (np.atleast_1d(P[k]) - step_k).reshape(np.shape(P[k]))
        if s == 1: first_update = {k: float(np.max(np.abs(v))) for k, v in upd.items()}
        record(s, loss)
    return P, hist, mu_path, first_update

# first steps from the start, no dropout, on the full triangle
P_a, hist_a, _, first_upd = rmsprop_run(P0, odp, y_full, OBS, steps=3, seed=1, dropout=False)
out["rmsprop_first_step"] = dict(theory=lr / math.sqrt(1 - rho), max_abs_update_by_group=first_upd,
                                 deviance_steps_0_to_3=[h["train"] for h in hist_a])

# ---------------------------------------------------------------- toy early stopping (claims split) ---
odp_tr = fit_odp(y_half1)
vali = np.where(OBS, y_half2, np.nan)
P_tr = init_params(odp_tr, seed=2026)
max_epochs = int(os.environ.get('MAXEP', '1000'))
P_end, hist, mu_path, _ = rmsprop_run(P_tr, odp_tr, y_half1, OBS, steps=max_epochs, seed=2026, dropout=True, track=dict(vali=vali))
vali_curve = np.array([h["vali"] for h in hist]); train_curve = np.array([h["train"] for h in hist])
best = int(np.argmin(vali_curve))
def loss_decrease(hist, step, window=10):
    at = lambda col, e: hist[e][col]
    w = min(window, step); near = [h["train_dropout"] for h in hist if step + 1 - w <= h["epoch"] <= step + 1 + w]
    return dict(train=1 - at("train", step) / at("train", 0), vali=1 - at("vali", step) / at("vali", 0),
                train_dropout=0.0 if step == 0 else 1 - np.mean(near) / at("train_dropout", 1))
dec = loss_decrease(hist, best)
out["toy_claims_split"] = dict(max_epochs=max_epochs, best_epoch=best, vali_start=float(vali_curve[0]), vali_best=float(vali_curve[best]),
                               train_start=float(train_curve[0]), train_at_best=float(train_curve[best]), train_end=float(train_curve[-1]),
                               vali_end=float(vali_curve[-1]), decrease=dec,
                               c_train_half=odp_tr["c"], c_full=odp["c"], log2=math.log(2),
                               max_abs_diff_alpha_halves=float(np.max(np.abs(odp_tr["alpha"] - odp["alpha"]))),
                               max_abs_diff_beta_halves=float(np.max(np.abs(odp_tr["beta"] - odp["beta"]))))
# refit on the full triangle for `best` steps from the full ccODP start
P_f, hist_f, mu_path_f, _ = rmsprop_run(P0, odp, y_full, OBS, steps=best, seed=2026, dropout=True,
                                      track=dict(truth=np.where(FUT, y_full, np.nan)))
mu_nn = mu_path_f[-1]
phi_nn = odp["phi"] * (1 - max(0.0, dec["vali"]))
out["toy_refit"] = dict(steps=best, reserve_bccnn=float(mu_nn[FUT].sum()), reserve_cl=odp["reserve"], true=out["data"]["true_reserve"],
                        bias_bccnn=float(mu_nn[FUT].sum() - out["data"]["true_reserve"]), bias_cl=odp["reserve"] - out["data"]["true_reserve"],
                        in_sample_dev_cl=odp["deviance"], in_sample_dev_bccnn=hist_f[-1]["train"],
                        oos_dev_cl=poisson_deviance(np.where(FUT, y_full, np.nan), odp["mu"]), oos_dev_bccnn=hist_f[-1]["truth"],
                        phi_cl=odp["phi"], phi_bccnn=phi_nn,
                        cum_dev_factor_row_spread_bccnn=float(np.max(cum_dev_factors(mu_nn).max(0) - cum_dev_factors(mu_nn).min(0))))


# ---------------------------------------------------------------- distance from the start, process variance, bootstrap ---
dist = {k: float(np.max(np.abs(np.atleast_1d(P_f[k]) - np.atleast_1d(P0[k])))) for k in P0}
out["distance_from_start"] = dict(steps=best, bound=lr / math.sqrt(1 - rho) * best, max_abs_by_group=dist,
                                  max_abs_overall=max(dist.values()),
                                  max_abs_correction_log_scale=float(np.max(np.abs(np.log(mu_nn / odp["mu"]))[:, np.where(OBS, y_full, 0).sum(0) > 0])),
                                  max_abs_correction_log_scale_lower_triangle=float(np.max(np.abs(np.log(mu_nn / odp["mu"]))[FUT & (np.where(OBS, y_full, 0).sum(0) > 0)[None, :].repeat(n, 0)])))
pv_cl = odp["phi"] * odp["reserve"]; pv_nn = phi_nn * float(mu_nn[FUT].sum())
out["process_variance"] = dict(cl=pv_cl, cl_sd=math.sqrt(pv_cl), bccnn=pv_nn, bccnn_sd=math.sqrt(pv_nn))
BOOT = int(os.environ.get("BOOT", "0"))
if BOOT > 0:
    rb = np.random.default_rng(99)
    res_cl = []; res_nn = []
    for b in range(BOOT):
        ystar = np.where(OBS, odp["phi"] * rb.poisson(np.where(OBS, odp["mu"], 0) / odp["phi"]), np.nan)   # ODP(mu_cc, phi) on the upper triangle
        odp_b = fit_odp(np.where(OBS, ystar, 0))
        P_b = init_params(odp_b, seed=2026)
        _, _, path_b, _ = rmsprop_run(P_b, odp_b, np.where(OBS, ystar, 0), OBS, steps=best, seed=2026, dropout=True)
        res_cl.append(odp_b["reserve"]); res_nn.append(float(path_b[-1][FUT].sum()))
    res_cl = np.array(res_cl); res_nn = np.array(res_nn)
    out["bootstrap"] = dict(B=BOOT, generating_model="ccODP(mu_cc, phi_D)", steps=best,
                            cl_mean=float(res_cl.mean()), cl_sd=float(res_cl.std(ddof=1)),
                            bccnn_mean=float(res_nn.mean()), bccnn_sd=float(res_nn.std(ddof=1)),
                            corr=float(np.corrcoef(res_cl, res_nn)[0, 1]),
                            msep_cl=pv_cl + float(res_cl.var(ddof=1)), msep_bccnn=pv_nn + float(res_nn.var(ddof=1)),
                            rmsep_cl=math.sqrt(pv_cl + float(res_cl.var(ddof=1))), rmsep_bccnn=math.sqrt(pv_nn + float(res_nn.var(ddof=1))))
# seed study of the refit
SEEDS = int(os.environ.get("SEEDS", "0"))
if SEEDS > 0:
    rs = []
    for sd in range(1, SEEDS + 1):
        P_s = init_params(odp, seed=sd)
        _, _, path_s, _ = rmsprop_run(P_s, odp, y_full, OBS, steps=best, seed=sd, dropout=True)
        rs.append(float(path_s[-1][FUT].sum()))
    rs = np.array(rs)
    out["seed_study"] = dict(K=SEEDS, steps=best, mean=float(rs.mean()), sd=float(rs.std(ddof=1)), min=float(rs.min()), max=float(rs.max()),
                             nagging=float(rs.mean()), reserves=[float(v) for v in rs])

# ---------------------------------------------------------------- figures ---
plt.rcParams.update({"font.size": 9, "font.family": "DejaVu Sans"})
fig, ax = plt.subplots(2, 1, figsize=(6.6, 5.6), sharex=True)
ep = np.arange(max_epochs + 1)
ax[0].plot(ep, [h["train_dropout"] for h in hist], ".", ms=2, color="tab:blue", label="training loss as Keras reports it (with dropout)")
ax[0].plot(ep, train_curve, "-", lw=1.2, color="black", label="in-sample deviance without dropout (training half)")
ax[0].set_ylabel("deviance, training half"); ax[0].legend(loc="upper right", fontsize=7.5)
ax[1].plot(ep, vali_curve, "-", lw=1.2, color="tab:red", label="validation deviance (validation half)")
ax[1].axvline(best, ls=":", color="black"); ax[1].text(best, vali_curve.max(), f"  $t^*$ = {best}", fontsize=8, va="top", ha="left")
ax[1].set_xlabel("gradient-descent step $t$ (= epoch, full batch)"); ax[1].set_ylabel("deviance, validation half"); ax[1].legend(loc="lower right", fontsize=7.5)
for a in ax: a.grid(alpha=0.3)
fig.tight_layout(); fig.savefig(OUTDIR + "/figures/toy_early_stopping.png", dpi=170); plt.close(fig)

# relative difference heatmap of the toy refit, and the true interaction
fig, ax = plt.subplots(1, 2, figsize=(7.4, 3.4))
rel = mu_nn / odp["mu"] - 1
zero_dev = (np.where(OBS, y_full, 0).sum(0) == 0)          # development periods without payments: effect -inf, ratio meaningless
rel[:, zero_dev] = np.nan
vmax = np.nanmax(np.abs(rel))
cmap = matplotlib.colormaps["RdBu_r"].copy(); cmap.set_bad("#d9d9d9")
out["toy_refit"]["zero_dev_periods"] = [int(j + 1) for j in np.where(zero_dev)[0]]
im = ax[0].imshow(rel, cmap=cmap, vmin=-vmax, vmax=vmax, origin="upper", extent=(0.5, n + .5, n + .5, 0.5))
ax[0].plot([0.5, n + .5], [n + .5, 0.5], color="black", lw=0.8)
ax[0].set_title(r"toy refit: $\mu^{bCCNN}_{i,j}/\hat\mu^{cc}_{i,j}-1$ (grey: no payments)", fontsize=9); ax[0].set_xlabel("development period $j$"); ax[0].set_ylabel("accident period $i$")
plt.colorbar(im, ax=ax[0], fraction=0.046)
true_rel = np.exp(inter) * np.exp(odp["c"] + odp["alpha"][:, None] + odp["beta"][None, :]) / odp["mu"] - 1
true_rel = np.exp(inter) - 1                                 # the interaction built into the toy, free of estimation noise
true_rel[:, zero_dev] = np.nan
vmax2 = np.nanmax(np.abs(true_rel))
im2 = ax[1].imshow(true_rel, cmap=cmap, vmin=-vmax2, vmax=vmax2, origin="upper", extent=(0.5, n + .5, n + .5, 0.5))
ax[1].plot([0.5, n + .5], [n + .5, 0.5], color="black", lw=0.8)
ax[1].set_title(r"the interaction built into the toy: $e^{\gamma (i-10.5)(j-4.5)\,\mathbf{1}\{j \leq 12\}}-1$", fontsize=9); ax[1].set_xlabel("development period $j$")
plt.colorbar(im2, ax=ax[1], fraction=0.046)
fig.tight_layout(); fig.savefig(OUTDIR + "/figures/toy_relative_difference.png", dpi=170); plt.close(fig)

# gradient norms by parameter group at the start, after 1 and after 2 steps (no dropout)
groups = ["c", "w", "B", "b3", "W3", "b2", "W2", "b1", "W1"]
norms = []
Pg = {k: np.array(v, dtype=float) for k, v in P0.items()}
Vg = {k: np.zeros_like(np.atleast_1d(v)) for k, v in Pg.items()}
yy = y_full[OBS]; N = yy.size
for s in range(3):
    F = forward(Pg, odp["alpha"], odp["beta"], OBS)
    G = backward(Pg, F, (F["mu"] - yy) / N)
    norms.append([float(np.linalg.norm(np.atleast_1d(G[k]))) for k in groups])
    for k in Pg:
        g = np.atleast_1d(G[k]).astype(float); Vg[k] = rho * Vg[k] + (1 - rho) * g * g
        Pg[k] = (np.atleast_1d(Pg[k]) - lr * g / (np.sqrt(Vg[k]) + eps)).reshape(np.shape(Pg[k]))
out["gradient_norms_first_steps"] = dict(groups=groups, step0=norms[0], step1=norms[1], step2=norms[2])
fig, ax = plt.subplots(figsize=(6.6, 2.9))
x = np.arange(len(groups)); wdt = 0.27
for s in range(3):
    vals = np.array(norms[s]); vals = np.where(vals > 0, vals, 1e-20)
    ax.bar(x + (s - 1) * wdt, vals, wdt, label=f"after {s} step{'s' if s != 1 else ''}")
ax.set_yscale("log"); ax.set_ylim(1e-16, None); ax.set_xticks(x); ax.set_xticklabels([f"${g}$" if len(g) == 1 else f"${g[0]}^{{({g[1]})}}$" for g in groups])
ax.set_ylabel("norm of the gradient\n(Keras loss, full batch)"); ax.legend(fontsize=7.5); ax.grid(alpha=0.3, axis="y")
fig.tight_layout(); fig.savefig(OUTDIR + "/figures/gradient_norms_first_steps.png", dpi=170); plt.close(fig)

def conv(o):
    if isinstance(o, dict): return {k: conv(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [conv(v) for v in o]
    if isinstance(o, (np.floating, np.integer)): return o.item()
    if isinstance(o, np.ndarray): return o.tolist()
    return o
json.dump(conv(out), open(OUTDIR + "/results.json", "w"), indent=1)
print(json.dumps(conv(out), indent=1))
