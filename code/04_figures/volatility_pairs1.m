%% volatility_pairs.m
% annualized standard deviation (volatility) vs time
% Output naming matches correlation naming:
%   <CROSSPAIR>_<NUMERAIRE>_volatility.png
% Example: EURUSD_JPY_volatility.png

clear; clc;

%% ------------------- SETTINGS -------------------
base_path = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated");

xlsxFile = fullfile(base_path, "Results_ALL_updated.xlsx");
outDir   = fullfile(base_path, "fig5b_volatility_matlab");

% Horizon used when we generated Results:
%   1M results  -> horizon_months = 1  -> annual factor = 12
%   3M results  -> horizon_months = 3  -> annual factor = 4
horizon_months = 1;

% How to handle negative variances (numerical noise):
%   "nan" -> drop these points (gaps in line)
%   "zero"-> clip to 0 (continuous line but can show spikes to 0)
neg_mode = "nan";

% axis labels
X_LABEL = "Date";
Y_LABEL = "Annualized standard deviation";
%% -----------------------------------------------------

if ~exist(xlsxFile, "file")
    error("Excel file not found: %s", xlsxFile);
end
if ~exist(outDir, "dir"); mkdir(outDir); end

annual_factor = 12 / horizon_months;    % 1M->12, 3M->4

% Sheets to process
sheets = sheetnames(xlsxFile);

% ignore helper sheets
ignore = upper(string(["INDEX","TICKERS_USED","RATE_COVERAGE","EOD_TIMES"]));
sheets = sheets(~ismember(upper(string(sheets)), ignore));

% keep only triangle sheets (those that have corr_hat)
keep = false(size(sheets));
for i = 1:numel(sheets)
    try
        opts = detectImportOptions(xlsxFile, "Sheet", sheets{i}, "PreserveVariableNames", true);
        keep(i) = any(strcmp(opts.VariableNames, "corr_hat"));
    catch
        keep(i) = false;
    end
end
sheets = sheets(keep);

fprintf("Found %d triangle sheets.\n", numel(sheets));

for i = 1:numel(sheets)
    sh = sheets{i};

    T = readtable(xlsxFile, "Sheet", sh, "PreserveVariableNames", true);

    % Normalize date column
    if any(strcmp(T.Properties.VariableNames,"Var1"));      T = renamevars(T,"Var1","date"); end
    if any(strcmp(T.Properties.VariableNames,"Unnamed_0")); T = renamevars(T,"Unnamed_0","date"); end

    if ~any(strcmp(T.Properties.VariableNames,"date"))
        warning("Sheet %s has no date column. Skipping.", sh);
        continue;
    end

    % Parse + sort dates
    dt = parseDateRobust(T.date);
    if all(isnat(dt))
        warning("Sheet %s: could not parse dates. Skipping.", sh);
        continue;
    end
    dt = dateshift(dt, "start","day");
    [dt, idx] = sort(dt);
    T = T(idx,:);

    % Find two legs from ret_var columns
    [leg1, leg2, col1, col2] = inferLegsFromRetVar(T.Properties.VariableNames);
    if col1 == "" || col2 == ""
        warning("Sheet %s: could not find two ret_var_ columns. Skipping.", sh);
        continue;
    end

    rv1 = T.(col1);
    rv2 = T.(col2);

    % Clean: non-finite -> NaN
    rv1(~isfinite(rv1)) = NaN;
    rv2(~isfinite(rv2)) = NaN;

    % Handle negative variances (numerical noise)
    switch lower(string(neg_mode))
        case "nan"
            rv1(rv1 < 0) = NaN;
            rv2(rv2 < 0) = NaN;
        case "zero"
            rv1(rv1 < 0) = 0;
            rv2(rv2 < 0) = 0;
        otherwise
            error("neg_mode must be 'nan' or 'zero'.");
    end

    % Annualized vol
    vol1 = sqrt(rv1) * sqrt(annual_factor);
    vol2 = sqrt(rv2) * sqrt(annual_factor);

    % Use numeric x for plotting (avoids axis-type errors)
    x = datenum(dt);

    % Build filename label that matches your correlation naming convention
    label = triangleLabelFromLegs(leg1, leg2);  % e.g. "EURUSD_JPY"
    if strlength(label) == 0
        % fallback to sheet name if something unexpected happens
        label = string(sh);
    end

    fig = figure("Visible","off","Color","w");
    plot(x, vol1); hold on;
    plot(x, vol2); grid on; hold off;

    datetick("x","yyyy","keeplimits");
    xlabel(X_LABEL);
    ylabel(Y_LABEL);

    legend(formatPair(leg1), formatPair(leg2), "Location", "northeast");

    % Title: use the same label as filename (more consistent than sheet name)
    title(label, "Interpreter","none");

    safeName = regexprep(label, '[\\/:*?"<>| ]', '_');
    outPng = fullfile(outDir, safeName + "_volatility.png");
    saveas(fig, outPng);
    close(fig);

    fprintf("Saved: %s\n", outPng);
end

fprintf("Done. All plots saved to: %s\n", outDir);

%% -------------------- helper functions --------------------

function [leg1, leg2, col1, col2] = inferLegsFromRetVar(varNames)
    v = string(varNames);
    rv = v(startsWith(v, "ret_var_"));
    if numel(rv) < 2
        leg1 = ""; leg2 = ""; col1 = ""; col2 = "";
        return;
    end
    col1 = rv(1);
    col2 = rv(2);
    leg1 = erase(col1, "ret_var_");
    leg2 = erase(col2, "ret_var_");
end

function label = triangleLabelFromLegs(leg1, leg2)
    % leg format is like "EURJPY", "USDJPY" etc.
    % numeraire = common quote currency of the two legs (last 3 chars)
    % crosspair = exchange rate between the two base currencies (first 3 chars),
    %            with rule: if one base is USD and the other isn't, put non-USD first.
    label = "";

    l1 = char(leg1); l2 = char(leg2);
    if numel(l1) ~= 6 || numel(l2) ~= 6
        return;
    end

    b1 = string(l1(1:3)); q1 = string(l1(4:6));
    b2 = string(l2(1:3)); q2 = string(l2(4:6));

    if q1 ~= q2
        % Not a standard "two legs share quote currency" case
        return;
    end

    numeraire = q1;

    % Decide cross order
    if (b1 == "USD" && b2 ~= "USD")
        a = b2; b = b1;   % non-USD first
    else
        a = b1; b = b2;   % keep original order
    end

    cross = a + b;        % e.g. EUR + USD -> "EURUSD"
    label = cross + "_" + numeraire;
end

function s = formatPair(pairStr)
    p = char(pairStr);
    if numel(p) == 6
        s = string(p(1:3)) + "/" + string(p(4:6));
    else
        s = string(pairStr);
    end
end

function dt = parseDateRobust(x)
    % Accepts:
    %  - Excel serial numbers
    %  - datetime already
    %  - string/cellstr like '2008-01-03' or '03/01/2008'
    % Returns datetime with NaT where it fails.

    if isdatetime(x)
        dt = x;
        return;
    end

    % Excel numeric serial
    if isnumeric(x)
        try
            dt = datetime(x, "ConvertFrom", "excel");
            return;
        catch
            dt = NaT(size(x));
            return;
        end
    end

    % cell array -> string
    if iscell(x)
        x = string(x);
    else
        x = string(x);
    end

    % Try common formats
    fmts = ["yyyy-MM-dd","dd/MM/yyyy","MM/dd/yyyy","dd-MMM-yyyy","yyyy/MM/dd"];
    dt = NaT(size(x));

    for k = 1:numel(fmts)
        try
            tmp = datetime(x, "InputFormat", fmts(k));
            mask = isnat(dt) & ~isnat(tmp);
            dt(mask) = tmp(mask);
        catch
        end
    end

    % Last resort: let MATLAB guess
    try
        tmp = datetime(x);
        mask = isnat(dt) & ~isnat(tmp);
        dt(mask) = tmp(mask);
    catch
    end
end