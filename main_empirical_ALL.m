%% Empirical estimation in currency markets — ALL triangles (Results struct)

% Parameters
base_path = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated");

xlsxFile = fullfile(base_path, "fx_prices_strikes_ALL.xlsx");

infer_prices = false;
tenor = '1M';
n_grid = 700;
a1 = 0.97; a2 = 0.97;

% Triangle sets
pair_sets = struct();
pair_sets.EURGBP = {'EURUSD','GBPUSD','EURGBP'};
pair_sets.EURJPY = {'EURUSD','USDJPY','EURJPY'};
pair_sets.EURCHF = {'EURUSD','USDCHF','EURCHF'};
pair_sets.EURAUD = {'EURUSD','AUDUSD','EURAUD'};
pair_sets.EURCAD = {'EURUSD','USDCAD','EURCAD'};
%pair_sets.EURNZD = {'EURUSD','NZDUSD','EURNZD'};

pair_sets.GBPJPY = {'GBPUSD','USDJPY','GBPJPY'};
%pair_sets.GBPCHF = {'GBPUSD','USDCHF','GBPCHF'};
pair_sets.GBPAUD = {'GBPUSD','AUDUSD','GBPAUD'};
%pair_sets.GBPCAD = {'GBPUSD','USDCAD','GBPCAD'};

pair_sets.AUDJPY = {'AUDUSD','USDJPY','AUDJPY'};
%pair_sets.NZDJPY = {'NZDUSD','USDJPY','NZDJPY'};
pair_sets.CADJPY = {'USDCAD','USDJPY','CADJPY'};
%pair_sets.AUDNZD = {'AUDUSD','NZDUSD','AUDNZD'};

if infer_prices
    fx_make_prices_all;
end

% Helper names for columns
option_names = ["P_10","P_25","P_ATM","C_25","C_10"] + "d_T" + tenor;
option_names(contains(option_names,"ATM")) = "P_ATM_T" + tenor;
strike_names = ["K_P10","K_P25","K_ATM","K_C25","K_C10"] + "_T" + tenor;
idx_P = 1:3; idx_C = 4:5;

% Projection basis functions
phi_marginal = @(x, Kp, Kc) [ones(numel(x),1), x, max(Kp' - x, 0), max(x - Kc', 0)];
beta_hat_var  = @(x, Kp, Kc, f) phi_marginal(x, Kp, Kc) \ (x - f).^2;
beta_hat_ent  = @(x, Kp, Kc, f) phi_marginal(x, Kp, Kc) \ log(x./f);
beta_hat_marg = @(x, Kp, Kc, f, a) phi_marginal(x, Kp, Kc) \ (x./f <= a);
target_tail_fun = @(x1,x2,F1,F2,a1,a2) double( (x1./F1 <= a1) & (x2./F2 <= a2) );

% List sheets once
sheets = sheetnames(xlsxFile);

% Output struct
Results = struct();
setNames = fieldnames(pair_sets);

for s = 1:numel(setNames)
    setName = setNames{s};
    pairs = pair_sets.(setName);

    fprintf("\n=== Running triangle %s: %s, %s, %s ===\n", setName, pairs{1}, pairs{2}, pairs{3});

    % --- Load the 3 tables into FX_data struct ---
    FX_data = struct();
    for i = 1:3
        pairStr = string(pairs{i});                 % "GBPUSD"
        pairFld = toField(pairStr);                 % safe struct field

        sh = find_sheet_for_setpair(sheets, setName, pairStr);
        T = readtable(xlsxFile, 'Sheet', sh, 'PreserveVariableNames', true);

        % normalize date column name
        if any(strcmp(T.Properties.VariableNames,"Var1"))
            T = renamevars(T,"Var1","date");
        end
        if any(strcmp(T.Properties.VariableNames,"Unnamed_0"))
            T = renamevars(T,"Unnamed_0","date");
        end
        if ~any(strcmp(T.Properties.VariableNames,"date"))
            error("Sheet %s has no date column.", sh);
        end

        % normalize dates to day
        T.date = dateshift(datetime(T.date), 'start', 'day');

        FX_data.(pairFld) = T;
    end

    % --- Determine legs + cross automatically ---
    [leg_num, leg_den, cross] = identify_triangle_roles(pairs{1}, pairs{2}, pairs{3});
    leg_num = string(leg_num); leg_den = string(leg_den); cross = string(cross);
    conv_pair = leg_den;

    legNumFld  = toField(leg_num);
    legDenFld  = toField(leg_den);
    crossFld   = toField(cross);
    convFld    = toField(conv_pair);

    % --- Align dates across the 3 pairs ---
    fn = fieldnames(FX_data);                     % these are field-safe already
    nrows = cellfun(@(f) height(FX_data.(f)), fn);
    [~, ix] = min(nrows);
    all_dates = FX_data.(fn{ix}).date;

    for i = setdiff(1:numel(fn), ix)
        temp = FX_data.(fn{i});
        FX_data.(fn{i}) = temp(ismember(temp.date, all_dates), :);
    end

    % --- Keep only desired tenor columns (plus date/spot) ---
    % safer than positional columns: keep date, spot, and anything containing tenor
    baseVars = ["date","spot"];
    vnames = string(FX_data.(fn{1}).Properties.VariableNames);
    tenorVars = vnames(contains(vnames, tenor));
    keepVars = unique([baseVars, tenorVars], 'stable');

    FX_tenor = struct();
    for i = 1:numel(fn)
        temp = FX_data.(fn{i});
        missing = setdiff(keepVars, string(temp.Properties.VariableNames));
        if ~isempty(missing)
            error("Pair %s is missing expected columns: %s", fn{i}, strjoin(missing, ", "));
        end
        FX_tenor.(fn{i}) = temp(:, cellstr(keepVars));
    end

    % --- Precompute expiry dates ---
    exp_date = arrayfun(@(d) fxOneMonthExpiry(d, 2), all_dates);
    exp_date = dateshift(exp_date, 'start', 'day');

    % --- Preallocate outputs ---
    N = numel(all_dates);
    corr_hat = NaN(N,1);
    var_1 = NaN(N,1); var_2 = NaN(N,1);
    ret_var_1 = NaN(N,1); ret_var_2 = NaN(N,1);
    ent_1 = NaN(N,1); ent_2 = NaN(N,1); ent_cross = NaN(N,1);
    integrate_var_cross = NaN(N,1);
    tail_risk = NaN(N,1);
    cond_tail_risk = NaN(N,1);
    marginal_hat_1 = NaN(N,1); marginal_hat_2 = NaN(N,1);
    ret = NaN(N,3);

    % --- Main loop ----------------------------
    parfor t = 1:N
        cur_date = all_dates(t);

        % containers per day
        stockGrid = struct();
        F = struct(); K = struct(); prices = struct(); risk_free = struct();
        ret_temp = NaN(1,3);

        triPairs = {leg_num, leg_den, cross};        % cell of strings
        triFlds  = {legNumFld, legDenFld, crossFld}; % cell of chars (valid struct fields)

        for j = 1:3
            pairStr = triPairs{j};   % string like "EURUSD"
            pairFld = triFlds{j};    % char like 'EURUSD' (field name)

            tempAll = FX_tenor.(pairFld);
            tempAll.date = dateshift(datetime(tempAll.date), 'start', 'day');
            % spot at expiry (for realized return)
            rowExp = tempAll(tempAll.date == exp_date(t), :);
            if isempty(rowExp)
                S_T = NaN;
            else
                S_T = rowExp.spot;
            end

            % row today
            rowCur = tempAll(tempAll.date == cur_date, :);
            if isempty(rowCur)
                continue;
            end
            temp = rowCur;

            % core inputs
            Dd = temp.("Dd_T" + tenor);
            Fp = temp.("F_T" + tenor);
            if ~isfinite(Dd) || ~isfinite(Fp)
                continue;
            end

            risk_free.(pairFld) = 1/Dd; % gross factor
            F.(pairFld) = Fp;
            ret_temp(j) = S_T / Fp;

            optVals = temp{:, option_names}';
            Kvals   = temp{:, strike_names}';
            if any(~isfinite(optVals)) || any(~isfinite(Kvals))
                continue;
            end

            if pairStr == cross
                % convert cross quote currency -> legs quote currency using F(conv_pair)
                if ~isfield(F, convFld) || ~isfield(risk_free, pairFld)
                    continue;
                end
                prices.(pairFld) = F.(convFld) * risk_free.(pairFld) * optVals;
            else
                prices.(pairFld) = [F.(pairFld); risk_free.(pairFld) * optVals];
            end

            K.(pairFld) = Kvals;
            stockGrid.(pairFld) = linspace(0.95*min(Kvals), 1.02*max(Kvals), n_grid)';
        end

        % If essential fields missing, store returns and skip
        if ~isfield(F, legNumFld) || ~isfield(F, legDenFld) || ~isfield(K, crossFld) || ...
           ~isfield(prices, legNumFld) || ~isfield(prices, legDenFld) || ~isfield(prices, crossFld)
            ret(t,:) = ret_temp;
            continue;
        end

        % Stack prices (order must match Phi columns)
        prices_stacked = [1; prices.(legNumFld); prices.(legDenFld); prices.(crossFld)];

        % Tensor grid
        x1 = stockGrid.(legNumFld);
        x2 = stockGrid.(legDenFld);
        x3 = stockGrid.(crossFld);

        [x1_ten, x2_ten] = meshgrid(x1, x2);
        x1_ten = x1_ten(:); x2_ten = x2_ten(:);

        % Covariance projection basis
        Phi = [ones(numel(x1_ten),1), x1_ten, ...
               max(K.(legNumFld)(idx_P)' - x1_ten,0), max(x1_ten - K.(legNumFld)(idx_C)',0), ...
               x2_ten, ...
               max(K.(legDenFld)(idx_P)' - x2_ten,0), max(x2_ten - K.(legDenFld)(idx_C)',0), ...
               x2_ten .* max(K.(crossFld)(idx_P)' - x1_ten./x2_ten,0), ...
               x2_ten .* max(x1_ten./x2_ten - K.(crossFld)(idx_C)',0)];

        target = (x1_ten - F.(legNumFld)) .* (x2_ten - F.(legDenFld));
        beta_hat = Phi \ target;
        cov_hat = beta_hat' * prices_stacked;

        % Variances & correlation
        v1 = beta_hat_var(x1, K.(legNumFld)(idx_P), K.(legNumFld)(idx_C), F.(legNumFld))' * [1; prices.(legNumFld)];
        v2 = beta_hat_var(x2, K.(legDenFld)(idx_P), K.(legDenFld)(idx_C), F.(legDenFld))' * [1; prices.(legDenFld)];

        if isfinite(v1) && isfinite(v2) && v1 > 0 && v2 > 0
            corr_hat(t) = cov_hat / sqrt(v1*v2);
        end
        var_1(t) = v1; var_2(t) = v2;
        ret_var_1(t) = v1 / (F.(legNumFld)^2);
        ret_var_2(t) = v2 / (F.(legDenFld)^2);

        % Entropy
        uk_prices = [1; F.(crossFld); prices.(crossFld) / F.(convFld)];
        ent_1(t) = -beta_hat_ent(x1, K.(legNumFld)(idx_P), K.(legNumFld)(idx_C), F.(legNumFld))' * [1; prices.(legNumFld)];
        ent_2(t) = -beta_hat_ent(x2, K.(legDenFld)(idx_P), K.(legDenFld)(idx_C), F.(legDenFld))' * [1; prices.(legDenFld)];
        ent_cross(t) = -beta_hat_ent(x3, K.(crossFld)(idx_P), K.(crossFld)(idx_C), F.(crossFld))' * uk_prices;

        % Integrated variance proxy for cross
        beta2 = beta_hat_log(x1_ten, x2_ten, F.(legNumFld), F.(legDenFld), K.(crossFld)(idx_P), K.(crossFld)(idx_C), phi_marginal);
        integrate_var_cross(t) = F.(convFld) * (-2 * beta2' * uk_prices);

        % Tail risk + conditional
        betaT = Phi \ target_tail_fun(x1_ten, x2_ten, F.(legNumFld), F.(legDenFld), a1, a2);
        tail_risk(t) = prices_stacked' * betaT;

        marginal_hat_1(t) = beta_hat_marg(x1, K.(legNumFld)(idx_P), K.(legNumFld)(idx_C), F.(legNumFld), a1)' * [1; prices.(legNumFld)];
        marginal_hat_2(t) = beta_hat_marg(x2, K.(legDenFld)(idx_P), K.(legDenFld)(idx_C), F.(legDenFld), a2)' * [1; prices.(legDenFld)];
        if isfinite(marginal_hat_2(t)) && marginal_hat_2(t) > 0
            cond_tail_risk(t) = tail_risk(t) / marginal_hat_2(t);
        end

        ret(t,:) = ret_temp;
    end

    % Pack output table Big (per triangle)
    R = array2table(ret, 'VariableNames', "ret_" + [leg_num, leg_den, cross]);
    R.date = all_dates(:);
    R = movevars(R, 'date', 'Before', 1);

    varNames = ["date","expiration_date","corr_hat", ...
        "var_" + leg_num, "var_" + leg_den, ...
        "ret_var_" + leg_num, "ret_var_" + leg_den, ...
        "ent_" + leg_num, "ent_" + leg_den, "ent_" + cross, ...
        "integrated_var_" + cross, ...
        "tail_risk","cond_tail_risk","marginal_hat_1","marginal_hat_2"];

    Stats = table(all_dates(:), exp_date(:), corr_hat(:), var_1(:), var_2(:), ...
        ret_var_1(:), ret_var_2(:), ent_1(:), ent_2(:), ent_cross(:), ...
        integrate_var_cross(:), tail_risk(:), cond_tail_risk(:), ...
        marginal_hat_1(:), marginal_hat_2(:), ...
        'VariableNames', varNames);

    Big = join(Stats, R, 'Keys', 'date');
    Results.(setName) = Big;
end

save(fullfile(base_path, "exchange_correlation_ALL.mat"), "Results", "a1", "a2");
fprintf("\nSaved: exchange_correlation_ALL.mat (struct Results)\n");

%% ---- Helper functions ----

function fld = toField(x)
    % Convert pair names safely to struct fields (parfor-safe)
    fld = matlab.lang.makeValidName(char(strtrim(string(x))));
end

function sh = find_sheet_for_setpair(sheets, setName, pair)
    target1 = string(setName) + "_" + string(pair);
    idx = find(strcmpi(string(sheets), target1), 1);
    if ~isempty(idx); sh = sheets{idx}; return; end

    idx = find(strcmpi(string(sheets), string(pair)), 1);
    if ~isempty(idx); sh = sheets{idx}; return; end

    idx = find(contains(upper(string(sheets)), upper(string(pair))), 1);
    if ~isempty(idx); sh = sheets{idx}; return; end
    error("No sheet found for %s (%s).", pair, setName);
end

function [leg_num, leg_den, cross] = identify_triangle_roles(p1, p2, p3)
    P = string({p1,p2,p3});
    base = extractBetween(P,1,3);
    quote = extractBetween(P,4,6);

    uq = unique(quote);
    counts = arrayfun(@(q) sum(quote==q), uq);
    idx = find(counts==2, 1);

    if isempty(idx)
        error("Triangle %s/%s/%s: cannot find two pairs with same quote currency.", p1,p2,p3);
    end

    N = uq(idx);
    legs = P(quote==N);
    cross = P(quote~=N);

    cross_base  = extractBetween(cross,1,3);
    cross_quote = extractBetween(cross,4,6);

    blegs = extractBetween(legs,1,3);
    num_idx = find(blegs==cross_base, 1);
    den_idx = find(blegs==cross_quote, 1);

    if isempty(num_idx) || isempty(den_idx)
        error("Triangle role identification failed for %s/%s/%s. Check pair directions.", p1,p2,p3);
    end

    leg_num = legs(num_idx);
    leg_den = legs(den_idx);
end

function beta = beta_hat_log(x1_ten,x2_ten,F1,F2,Kp,Kc,phi_marginal)
    target = log((x1_ten/F1)./(x2_ten/F2))./x2_ten;
    Phi = phi_marginal(x1_ten./x2_ten, Kp, Kc);
    beta = Phi \ target;
end
