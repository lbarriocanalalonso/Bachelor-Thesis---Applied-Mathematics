%% regressions_neweywest.m
% 9 pair-by-pair regressions:
%   y_it = c_i + beta1_i * covariance_it + beta2_i * tail_risk_it + eps_it
%
% 1 pooled panel regression with pair fixed effects:
%   y_it = alpha_i + beta1 * covariance_it + beta2 * tail_risk_it + eps_it
%
%   y_it = 1(R1 <= 0.97) * 1(R2 <= 0.97)
%   X_it = [covariance_it, tail_risk_it]
%
% Standard errors:
%   Newey-West (HAC) with bandwidth = 20

clear; clc;

%% ------------------------------------------------------------------------
% 1) Paths
% -------------------------------------------------------------------------
resultsPath = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated", "Results_ALL_updated1.xlsx");

assert(isfile(resultsPath), "Could not find file: %s", resultsPath);

outPath = fullfile(fileparts(resultsPath), "Regressions", "regression_results_neweywest.xlsx");

% Newey-West bandwidth (in observations / trading days)
nwLag = 20;

%% ------------------------------------------------------------------------
% 2) Read sheet names
% -------------------------------------------------------------------------
sheets = sheetnames(resultsPath);
sheets = sheets(~strcmpi(sheets, "INDEX"));

nPairs = numel(sheets);
assert(nPairs == 9, "Expected 9 triangle sheets, found %d.", nPairs);

%% ------------------------------------------------------------------------
% 3) Containers for pair-by-pair output
% -------------------------------------------------------------------------
pairNames = strings(nPairs,1);
Nobs       = zeros(nPairs,1);
MeanY      = zeros(nPairs,1);
R2_pair    = zeros(nPairs,1);

const_pair = zeros(nPairs,1);
se_const   = zeros(nPairs,1);
t_const    = zeros(nPairs,1);
p_const    = zeros(nPairs,1);

beta_cov   = zeros(nPairs,1);
se_cov     = zeros(nPairs,1);
t_cov      = zeros(nPairs,1);
p_cov      = zeros(nPairs,1);

beta_tail  = zeros(nPairs,1);
se_tail    = zeros(nPairs,1);
t_tail     = zeros(nPairs,1);
p_tail     = zeros(nPairs,1);

%% ------------------------------------------------------------------------
% 4) Containers for stacked panel
% -------------------------------------------------------------------------
Y_all       = [];
X_all       = [];
pair_id_all = [];

%% ------------------------------------------------------------------------
% 5) Loop over sheets: build y and X, then run pair-by-pair regressions
% -------------------------------------------------------------------------
for i = 1:nPairs
    sh = sheets(i);
    T = readtable(resultsPath, "Sheet", sh, "PreserveVariableNames", true);

    names = string(T.Properties.VariableNames);

    % If a date column exists, sort by date
    dateMask = ismember(lower(names), "date");
    if any(dateMask)
        dateCol = names(find(dateMask, 1));
        T = sortrows(T, dateCol);
        names = string(T.Properties.VariableNames);
    end

    % Required columns
    if ~ismember("corr_hat", names)
        error('Sheet "%s" is missing column "corr_hat".', sh);
    end
    if ~ismember("tail_risk", names)
        error('Sheet "%s" is missing column "tail_risk".', sh);
    end

    % Find the two var_* columns (to identify the two legs)
    varCols = names(startsWith(names, "var_"));
    if numel(varCols) ~= 2
        error('Sheet "%s": expected exactly 2 var_* columns, found %d.', sh, numel(varCols));
    end

    % Infer corresponding return columns
    leg1 = erase(varCols(1), "var_");
    leg2 = erase(varCols(2), "var_");

    ret1Col = "ret_" + leg1;
    ret2Col = "ret_" + leg2;

    if ~ismember(ret1Col, names) || ~ismember(ret2Col, names)
        error('Sheet "%s": missing return columns %s and/or %s.', sh, ret1Col, ret2Col);
    end

    % Extract series
    corr_hat  = T.corr_hat;
    var1      = T.(varCols(1));
    var2      = T.(varCols(2));
    tail_risk = T.tail_risk;
    ret1      = T.(ret1Col);
    ret2      = T.(ret2Col);

    % Build covariance from correlation and variances
    sigma1 = sqrt(max(var1, 0));
    sigma2 = sqrt(max(var2, 0));
    covariance = corr_hat .* sigma1 .* sigma2;

    % Realized joint-crash indicator
    y = double((ret1 <= 0.97) & (ret2 <= 0.97));

    % Regressors
    X = [covariance, tail_risk];

    % Keep valid rows only
    ok = all(isfinite(X), 2) & isfinite(y);
    X = X(ok, :);
    y = y(ok);

    if isempty(y)
        error('Sheet "%s": no valid rows after cleaning.', sh);
    end

    % Pair-by-pair regression: with intercept, Newey-West SEs
    stats_i = ols_newey_west(y, X, true, nwLag);

    % Store results
    pairNames(i) = string(sh);
    Nobs(i)      = stats_i.n;
    MeanY(i)     = mean(y);
    R2_pair(i)   = stats_i.R2;

    % Coefficient order with addIntercept = true:
    %   1 = constant, 2 = covariance, 3 = tail_risk
    const_pair(i) = stats_i.beta(1);
    se_const(i)   = stats_i.se(1);
    t_const(i)    = stats_i.t(1);
    p_const(i)    = stats_i.p(1);

    beta_cov(i)   = stats_i.beta(2);
    se_cov(i)     = stats_i.se(2);
    t_cov(i)      = stats_i.t(2);
    p_cov(i)      = stats_i.p(2);

    beta_tail(i)  = stats_i.beta(3);
    se_tail(i)    = stats_i.se(3);
    t_tail(i)     = stats_i.t(3);
    p_tail(i)     = stats_i.p(3);

    % Append to panel data
    Y_all       = [Y_all; y];
    X_all       = [X_all; X];
    pair_id_all = [pair_id_all; i * ones(numel(y),1)];
end

%% ------------------------------------------------------------------------
% 6) Pair-by-pair output table
% -------------------------------------------------------------------------
PairByPair = table( ...
    pairNames, Nobs, MeanY, ...
    const_pair, se_const, t_const, p_const, ...
    beta_cov, se_cov, t_cov, p_cov, ...
    beta_tail, se_tail, t_tail, p_tail, ...
    R2_pair, ...
    'VariableNames', { ...
    'Pair', 'N', 'MeanY', ...
    'Constant', 'SE_Constant', 't_Constant', 'p_Constant', ...
    'Beta_Covariance', 'SE_Covariance', 't_Covariance', 'p_Covariance', ...
    'Beta_TailRisk',   'SE_TailRisk',   't_TailRisk',   'p_TailRisk', ...
    'R2'});

%% ------------------------------------------------------------------------
% 7) Panel regression with pair fixed effects
% -------------------------------------------------------------------------
% Fixed effects implemented as one dummy per pair, no global intercept:
%   y_it = alpha_i + beta1 * covariance_it + beta2 * tail_risk_it + eps_it
%
% HAC is computed within pair only.

nTotal = numel(Y_all);

D = zeros(nTotal, nPairs);
for i = 1:nPairs
    D(:,i) = (pair_id_all == i);
end

X_fe = [D, X_all];

stats_fe = ols_newey_west(Y_all, X_fe, false, nwLag, pair_id_all);

beta_cov_panel  = stats_fe.beta(nPairs + 1);
se_cov_panel    = stats_fe.se(nPairs + 1);
t_cov_panel     = stats_fe.t(nPairs + 1);
p_cov_panel     = stats_fe.p(nPairs + 1);

beta_tail_panel = stats_fe.beta(nPairs + 2);
se_tail_panel   = stats_fe.se(nPairs + 2);
t_tail_panel    = stats_fe.t(nPairs + 2);
p_tail_panel    = stats_fe.p(nPairs + 2);

PanelFE = table( ...
    nTotal, mean(Y_all), ...
    beta_cov_panel, se_cov_panel, t_cov_panel, p_cov_panel, ...
    beta_tail_panel, se_tail_panel, t_tail_panel, p_tail_panel, ...
    stats_fe.R2, ...
    'VariableNames', { ...
    'N', 'MeanY', ...
    'Beta_Covariance', 'SE_Covariance', 't_Covariance', 'p_Covariance', ...
    'Beta_TailRisk',   'SE_TailRisk',   't_TailRisk',   'p_TailRisk', ...
    'R2'});

%% ------------------------------------------------------------------------
% 8) Write sheets
% -------------------------------------------------------------------------
if isfile(outPath)
    delete(outPath);
end

writetable(PairByPair, outPath, "Sheet", "PairByPair_NW20_Const");
writetable(PanelFE,    outPath, "Sheet", "PanelFE_NW20");

fprintf('\nDone.\n');
fprintf('Regression tables saved to:\n%s\n', outPath);

%% ========================================================================
% Helper: OLS with Newey-West (HAC) standard errors
% ========================================================================
function stats = ols_newey_west(y, X, addIntercept, L, groupId)

    y = y(:);

    % Ensure X is a matrix
    if isvector(X)
        X = X(:);
    end

    % Default: treat the whole sample as one time series
    if nargin < 5 || isempty(groupId)
        groupId = ones(size(y));
    else
        groupId = groupId(:);
    end

    if addIntercept
        X = [ones(size(X,1),1), X];
    end

    [n, k] = size(X);

    if size(y,1) ~= n
        error('y and X have incompatible dimensions.');
    end
    if size(groupId,1) ~= n
        error('groupId must have the same number of rows as y.');
    end

    % OLS estimates
    beta = X \ y;
    yhat = X * beta;
    u = y - yhat;

    % R^2
    if addIntercept
        TSS = sum((y - mean(y)).^2);
    else
        % Uncentered R^2 for no-intercept regressions
        TSS = sum(y.^2);
    end
    RSS = sum(u.^2);
    R2 = 1 - RSS / TSS;

    % Newey-West HAC variance estimator
    XtX_inv = pinv(X' * X);

    % z_t = x_t * u_t
    xu = bsxfun(@times, X, u);

    S = zeros(k, k);

    groups = unique(groupId, 'stable');

    for g = 1:numel(groups)
        idx = find(groupId == groups(g));
        Zg = xu(idx, :);      % observations for this group, in time order
        Tg = size(Zg, 1);

        % Lag 0 term
        S = S + (Zg' * Zg);

        % Lags 1..L with Bartlett weights
        maxLagHere = min(L, Tg - 1);
        for ell = 1:maxLagHere
            w = 1 - ell / (L + 1);
            Gamma = Zg((ell+1):end, :)' * Zg(1:(end-ell), :);
            S = S + w * (Gamma + Gamma');
        end
    end

    % Small-sample adjustment
    finiteSampleAdj = n / max(n - k, 1);

    V = finiteSampleAdj * XtX_inv * S * XtX_inv;

    % Numerical safeguard
    se = sqrt(max(diag(V), 0));

    % Asymptotic z-stats (kept in field "t" for compatibility)
    tstat = beta ./ se;
    pval  = erfc(abs(tstat) / sqrt(2));

    stats.beta = beta;
    stats.se   = se;
    stats.t    = tstat;
    stats.p    = pval;
    stats.R2   = R2;
    stats.n    = n;
    stats.k    = k;
    stats.u    = u;
    stats.yhat = yhat;
    stats.V    = V;
end
