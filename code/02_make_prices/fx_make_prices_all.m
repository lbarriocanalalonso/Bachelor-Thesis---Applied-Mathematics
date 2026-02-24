function fx_make_prices_all()
% fx_make_prices_all
% Build strikes and GK prices for ALL pairs (one sheet per pair), from:
%   - inputs Excel: fx_inputs_1m_3m_ALL_PAIRS.xlsx (one sheet per pair)
%   - vol CSVs: <PAIR>.csv or fxvol_<PAIR>.csv etc.

% Paths
base_path = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated");

inputsFile = fullfile(base_path, "fx_inputs_1m_3m_ALL_PAIRS_updated.xlsx");

% Vol folders to search
volDirs = { ...
    fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
        "2026 Bachelor Thesis", "FX_implied_vols_updated", "csv_vols"), ...
    fullfile(base_path, "csv_inputs"), ...
    fullfile(base_path, "FX_implied_vols_results_allpairs"), ...
    base_path ...
};

% Triangle sets (used ONLY to build pair universe)
pair_sets = struct();
pair_sets.EURGBP = {'EURUSD','GBPUSD','EURGBP'};
pair_sets.EURJPY = {'EURUSD','USDJPY','EURJPY'};
pair_sets.EURCHF = {'EURUSD','USDCHF','EURCHF'};
pair_sets.EURAUD = {'EURUSD','AUDUSD','EURAUD'};
pair_sets.EURCAD = {'EURUSD','USDCAD','EURCAD'};
pair_sets.GBPJPY = {'GBPUSD','USDJPY','GBPJPY'};
pair_sets.GBPAUD = {'GBPUSD','AUDUSD','GBPAUD'};
pair_sets.AUDJPY = {'AUDUSD','USDJPY','AUDJPY'};
pair_sets.CADJPY = {'USDCAD','USDJPY','CADJPY'};

% Tenors
tenors = {'T1M','T3M'};
Tyear  = struct('T1M',1/12,'T3M',3/12);

% Output Excel
outFile = fullfile(base_path, "fx_prices_strikes_ALL.xlsx");
if exist(outFile,'file'); delete(outFile); end

if ~isfile(inputsFile)
    error("Inputs file not found: %s", inputsFile);
end

% Build unique list of pairs, loop once
setNames = fieldnames(pair_sets);
allPairs = {};
for s = 1:numel(setNames)
    allPairs = [allPairs, pair_sets.(setNames{s})]; %#ok<AGROW>
end
allPairs = unique(allPairs, 'stable');

fprintf("Total unique pairs to process: %d\n", numel(allPairs));

for p = 1:numel(allPairs)
    pair = allPairs{p};
    fprintf("\n=== Processing pair: %s ===\n", pair);

    % 1) Read inputs (Excel)
    in = readtable(inputsFile,'Sheet',pair,'PreserveVariableNames',true);

    % normalize date column
    if any(strcmp(in.Properties.VariableNames,"Var1"))
        in = renamevars(in,"Var1","date");
    end
    if ~any(strcmp(in.Properties.VariableNames,"date"))
        error("Sheet %s must contain a date column (Var1 or date).", pair);
    end
    in.date = normalizeDate(in.date, sprintf("inputs sheet %s", pair));

    mustHaveInputs = ["spot","F_1M","F_3M"];
    for k = 1:numel(mustHaveInputs)
        if ~any(strcmp(in.Properties.VariableNames, mustHaveInputs(k)))
            error("Sheet %s missing column '%s'.", pair, mustHaveInputs(k));
        end
    end

    spot = in.spot;
    F_1M = in.F_1M;
    F_3M = in.F_3M;

    % domestic/foreign from pair code
    FOR = pair(1:3);   % base
    DOM = pair(4:6);   % quote

    % rate column names 
    rd1 = "r_d_" + DOM + "_1M";
    rd3 = "r_d_" + DOM + "_3M";
    rf1 = "r_f_" + FOR + "_1M";
    rf3 = "r_f_" + FOR + "_3M";

    mustHaveRates = [rd1 rd3 rf1 rf3];
    for k = 1:numel(mustHaveRates)
        if ~any(strcmp(in.Properties.VariableNames, mustHaveRates(k)))
            error("Sheet %s is missing column '%s'.", pair, mustHaveRates(k));
        end
    end

    % discount factors (simple compounding)
    Dd_1M = 1./(1 + in.(rd1).*Tyear.T1M);
    Dd_3M = 1./(1 + in.(rd3).*Tyear.T3M);
    Df_1M = 1./(1 + in.(rf1).*Tyear.T1M);
    Df_3M = 1./(1 + in.(rf3).*Tyear.T3M);

    % 2) Read vol CSV (pair-only naming supported)
    volFile = findVolFile(volDirs, pair);
    V = readVolFileFlexible(volFile);

    % Ensure C/P vols exist via ATM/BF/RR if missing
    V = ensureCPVols(V, tenors);

    % 3) Compute strikes & prices
    res = table(in.date, spot, 'VariableNames', {'date','spot'});

    MapF  = containers.Map({'T1M','T3M'}, {F_1M, F_3M});
    MapDd = containers.Map({'T1M','T3M'}, {Dd_1M, Dd_3M});
    MapDf = containers.Map({'T1M','T3M'}, {Df_1M, Df_3M});

    for t = 1:numel(tenors)
        Tn = tenors{t};
        T  = Tyear.(Tn);

        if ~isfield(V, Tn)
            fprintf("  (no %s vols in file for %s)\n", Tn, pair);
            continue;
        end

        F  = MapF(Tn);
        Dd = MapDd(Tn);
        Df = MapDf(Tn);

        Tin = table(in.date, F, Dd, Df, 'VariableNames', {'date','F','Dd','Df'});

        VT = V.(Tn);
        Tvol = table(VT.date, VT.ATM, VT.BF10, VT.BF25, VT.RR10, VT.RR25, VT.C25, VT.P25, VT.C10, VT.P10, ...
            'VariableNames', {'date','ATM','BF10','BF25','RR10','RR25','C25','P25','C10','P10'});

        Tjoin = innerjoin(Tin, Tvol, 'Keys', 'date');

        if isempty(Tjoin)
            warning("No overlapping dates between inputs and vols for %s %s.", pair, Tn);
            continue;
        end

        atm = Tjoin.ATM/100;
        F   = Tjoin.F;
        Dd  = Tjoin.Dd;
        Df  = Tjoin.Df;

        C25 = Tjoin.C25/100;  P25 = Tjoin.P25/100;
        C10 = Tjoin.C10/100;  P10 = Tjoin.P10/100;

        % ATM strike convention (your original)
        K_ATM = F .* exp(0.5 .* (atm.^2) .* T);
        price_ATM_call = gk_call(F, K_ATM, atm, T, Dd);
        price_ATM_put  = gk_put (F, K_ATM, atm, T, Dd);

        % 25D
        K_C25 = strike_from_spot_delta(0.25, true,  F, C25, T, Df);
        K_P25 = strike_from_spot_delta(0.25, false, F, P25, T, Df);
        price_C25 = gk_call(F, K_C25, C25, T, Dd);
        price_P25 = gk_put (F, K_P25, P25, T, Dd);

        % 10D
        K_C10 = strike_from_spot_delta(0.10, true,  F, C10, T, Df);
        K_P10 = strike_from_spot_delta(0.10, false, F, P10, T, Df);
        price_C10 = gk_call(F, K_C10, C10, T, Dd);
        price_P10 = gk_put (F, K_P10, P10, T, Dd);

        block = table(Tjoin.date, ...
            F, Dd, ...
            K_ATM, price_ATM_call, price_ATM_put, ...
            K_C25, K_P25, price_C25, price_P25, ...
            K_C10, K_P10, price_C10, price_P10, ...
            'VariableNames', { ...
            'date', ...
            sprintf('F_%s',Tn), sprintf('Dd_%s',Tn), ...
            sprintf('K_ATM_%s',Tn), sprintf('C_ATM_%s',Tn), sprintf('P_ATM_%s',Tn), ...
            sprintf('K_C25_%s',Tn), sprintf('K_P25_%s',Tn), sprintf('C_25d_%s',Tn), sprintf('P_25d_%s',Tn), ...
            sprintf('K_C10_%s',Tn), sprintf('K_P10_%s',Tn), sprintf('C_10d_%s',Tn), sprintf('P_10d_%s',Tn) ...
            });

        res = outerjoin(res, block, 'Keys','date', 'MergeKeys', true);
        res = sortrows(res,'date');
    end

    % ----------------------------
    % 4) Write sheet
    % ----------------------------
    sheetName = truncateSheetName(pair);  % "EURUSD", "GBPUSD", ...
    writetable(res, outFile, 'Sheet', sheetName);
end

fprintf("\nSaved master output: %s\n", outFile);
end

% Helpers
function volFile = findVolFile(volDirs, pair)

cands = { ...
    sprintf("%s.csv", pair), ...           
    sprintf("fxvol_%s.csv", pair), ...     
    sprintf("fxvol_%s_%s.csv", pair, pair) ... 
};

for d = 1:numel(volDirs)
    for c = 1:numel(cands)
        f = fullfile(volDirs{d}, cands{c});
        if isfile(f)
            volFile = f;
            fprintf("  Vol file: %s\n", volFile);
            return;
        end
    end
end

msg = "No vol CSV found for " + pair + ". Looked in:\n";
for d = 1:numel(volDirs)
    msg = msg + "  - " + string(volDirs{d}) + "\n";
end
msg = msg + "With names:\n";
for c = 1:numel(cands)
    msg = msg + "  - " + string(cands{c}) + "\n";
end
error(msg);
end

function sheetName = truncateSheetName(sheetName)
sheetName = regexprep(sheetName, '[:\\\/\?\*\[\]]', '_');
if strlength(sheetName) > 31
    sheetName = extractBetween(sheetName, 1, 31);
end
end

function V = readVolFileFlexible(volFile)


C = readcell(volFile);

if size(C,1) >= 3 && size(C,2) >= 3 && ischarlike(C{1,2}) && ischarlike(C{2,2})
    ten = string(C(1,2:end));
    mea = string(C(2,2:end));
    if any(mea == "ATM") && any(ten == "1M" | ten == "3M" | ten == "1W" | ten == "6M" | ten == "1Y")
        V = parseVolTwoHeader(C);
        return;
    end
end

T = readtable(volFile,'PreserveVariableNames',true);
V = extractVolsRobust(T);
end

function tf = ischarlike(x)
tf = ischar(x) || isstring(x);
end

function V = parseVolTwoHeader(C)
tenorsRow   = string(C(1,2:end));
measuresRow = string(C(2,2:end));

rawDates = C(3:end,1);
dates = normalizeDate(rawDates, "vol CSV dates");

X = C(3:end,2:end);
X = cellfun(@toNum, X);

measList = ["ATM","BF10","BF25","RR10","RR25","C10","P10","C25","P25"];

V = struct();
uTen = unique(tenorsRow,'stable');

for i = 1:numel(uTen)
    T = uTen(i);
    idxT = (tenorsRow == T);

    S = struct();
    S.date = dates;

    for m = 1:numel(measList)
        M = measList(m);
        idx = idxT & (measuresRow == M);
        if any(idx)
            S.(char(M)) = X(:, find(idx,1,'first'));
        else
            S.(char(M)) = nan(numel(dates),1);
        end
    end

    V.(fieldizeTenor(T)) = S;
end
end

function y = toNum(v)
if isnumeric(v)
    y = v;
elseif ismissing(v) || isempty(v)
    y = NaN;
else
    y = str2double(string(v));
    if isnan(y); y = NaN; end
end
end

function V = extractVolsRobust(volTab)

vnames = volTab.Properties.VariableNames;

% date col
if any(strcmpi(vnames,"date"))
    dateCol = vnames{strcmpi(vnames,"date")};
else
    dateCol = vnames{1};
end

d = volTab.(dateCol);
d = normalizeDate(d, "vol table date");
volTab.date = d;

if ~strcmp(dateCol,"date")
    volTab(:,dateCol) = [];
end
volTab = movevars(volTab,'date','Before',1);

% strip leading "t" like t1M_ATM -> 1M_ATM
v = volTab.Properties.VariableNames;
v = regexprep(v, '^t(?=\d)', '');
volTab.Properties.VariableNames = v;

tenors = {'1W','1M','3M','6M','1Y'};
measList = {'ATM','BF10','BF25','RR10','RR25','C10','P10','C25','P25'};

V = struct();

for i = 1:numel(tenors)
    T = tenors{i};
    S = struct();
    S.date = volTab.date;

    for m = 1:numel(measList)
        nm = T + "_" + measList{m};
        if any(strcmp(volTab.Properties.VariableNames, nm))
            S.(measList{m}) = volTab.(nm);
        else
            S.(measList{m}) = nan(height(volTab),1);
        end
    end

    if all(isnan(S.ATM))
        continue;
    end

    V.(fieldizeTenor(T)) = S;
end
end

function V = ensureCPVols(V, tenorsWanted)
for t = 1:numel(tenorsWanted)
    Tn = tenorsWanted{t};
    if ~isfield(V,Tn); continue; end
    S = V.(Tn);

    atm = S.ATM;

    for delt = ["10","25"]
        bfName = "BF" + delt;
        rrName = "RR" + delt;

        if ~isfield(S, bfName) || ~isfield(S, rrName)
            continue;
        end

        bf = S.(bfName);
        rr = S.(rrName);

        cName = "C" + delt;
        pName = "P" + delt;

        if ~isfield(S,cName) || all(isnan(S.(cName)))
            S.(cName) = atm + 0.5*(bf + rr);
        end
        if ~isfield(S,pName) || all(isnan(S.(pName)))
            S.(pName) = atm + 0.5*(bf - rr);
        end
    end

    V.(Tn) = S;
end
end

function f = fieldizeTenor(t)
% "1M" -> "T1M"
f = ['T' char(t)];
f = strrep(f,'-','_');
end

function d = normalizeDate(d, context)
if isdatetime(d); return; end

if isnumeric(d)
    d = datetime(d,'ConvertFrom','excel');
    return;
end

if iscell(d); d = string(d); end
if isstring(d) || ischar(d)
    d = string(d);

    fmts = ["yyyy-MM-dd","MM/dd/yyyy","dd/MM/yyyy","MM-dd-yyyy","dd-MMM-yyyy"];
    for f = fmts
        try
            dt = datetime(d,'InputFormat',f);
            if all(~isnat(dt))
                d = dt; return;
            end
        catch
        end
    end

    % last resort
    try
        d = datetime(d);
        if any(isnat(d))
            error("Could not parse some dates.");
        end
    catch
        error("Unrecognized date format in %s.", context);
    end
    return;
end

error("Unrecognized date type (%s) in %s.", class(d), context);
end

function c = gk_call(F, K, sigma, T, Dd)
d1 = (log(F./K) + 0.5*(sigma.^2).*T) ./ (sigma.*sqrt(T));
d2 = d1 - sigma.*sqrt(T);
c  = Dd .* ( F.*normcdf(d1) - K.*normcdf(d2) );
end

function p = gk_put(F, K, sigma, T, Dd)
d1 = (log(F./K) + 0.5*(sigma.^2).*T) ./ (sigma.*sqrt(T));
d2 = d1 - sigma.*sqrt(T);
p  = Dd .* ( K.*normcdf(-d2) - F.*normcdf(-d1) );
end

function K = strike_from_spot_delta(deltaAbs, isCall, F, sigma, T, Df)
if isCall
    DeltaF = min(max(deltaAbs ./ Df, 1e-6), 1-1e-6);
else
    DeltaF = min(max(1 - (deltaAbs ./ Df), 1e-6), 1-1e-6);
end
d1 = norminv(DeltaF);
K  = F .* exp( -sigma.*sqrt(T).*d1 + 0.5*(sigma.^2).*T );
end

