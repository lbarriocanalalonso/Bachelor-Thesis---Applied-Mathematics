%% correlation_pairs.m
% One plot per triangle sheet (corr_hat), with clear filenames and tight x-axis.
%
% Filename convention:
%   <BASE1><BASE2>_<QUOTE>_corr_hat.png

clear; clc;

%% --- Paths ---
base_path = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated");

xlsxFile = fullfile(base_path, "Results_ALL_updated.xlsx");
outDir   = fullfile(base_path, "correlation results");

if ~exist(xlsxFile, "file")
    error("Excel file not found: %s", xlsxFile);
end
if ~exist(outDir, "dir")
    mkdir(outDir);
end

%% ---------- Readability settings ----------
P_LO = 1;            % lower percentile for y-limits
P_HI = 99;           % upper percentile for y-limits
PAD_FRAC = 0.25;     % padding around percentile band
MIN_SPAN = 0.8;      % minimum visible span for y-axis

Y_VIS_MIN = -1.2;    % hard caps (safety)
Y_VIS_MAX =  1.2;

YTICK_STEP = 0.1;         % y tick step
XTICK_STEP_YEARS = 2;     % x tick every 2 years
SMOOTH_WINDOW = 0;        % 0 = OFF
%% ----------------------------------------

%% --- Sheets ---
sheets = sheetnames(xlsxFile);

ignore = upper(string(["INDEX","TICKERS_USED","RATE_COVERAGE","EOD_TIMES"]));
sheets = sheets(~ismember(upper(string(sheets)), ignore));

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

fprintf("Found %d triangle sheets with corr_hat.\n", numel(sheets));

%% --- Loop ---
for i = 1:numel(sheets)
    sh = sheets{i};

    T = readtable(xlsxFile, "Sheet", sh, "PreserveVariableNames", true);

    % Normalize date column if Excel used weird headers
    if any(strcmp(T.Properties.VariableNames,"Var1"))
        T = renamevars(T, "Var1", "date");
    end
    if any(strcmp(T.Properties.VariableNames,"Unnamed_0"))
        T = renamevars(T, "Unnamed_0", "date");
    end

    if ~any(strcmp(T.Properties.VariableNames,"date")) || ~any(strcmp(T.Properties.VariableNames,"corr_hat"))
        warning("Sheet %s missing date/corr_hat, skipped.", sh);
        continue;
    end

    % Parse dates
    dt = T.date;
    if ~isdatetime(dt)
        try
            if isnumeric(dt)
                dt = datetime(dt, "ConvertFrom", "excel");
            else
                dt = datetime(dt);
            end
        catch
            warning("Sheet %s: couldn't parse dates, skipped.", sh);
            continue;
        end
    end
    dt = dateshift(dt, "start", "day");

    % Series
    y = T.corr_hat;
    y(~isfinite(y)) = NaN;

    % Sort
    [dt, idx] = sort(dt);
    y = y(idx);

    % Remove duplicate dates by averaging
    [dtU, ~, g] = unique(dt);
    yU = accumarray(g, y, [], @(v) mean(v, "omitnan"));
    dt = dtU;
    y  = yU;

    % Optional smoothing
    if SMOOTH_WINDOW > 1
        y = movmean(y, SMOOTH_WINDOW, "omitnan");
    end

    % Infer the two legs being correlated from var_* columns
    [leg1, leg2] = inferLegsFromVars(T.Properties.VariableNames);

    % Build filename stem <BASE1><BASE2>_<QUOTE>
    baseQuoteName = buildCorrNameFromLegs(leg1, leg2);

    % === Tight x-axis: trim to first/last valid corr_hat ===
    valid = isfinite(y);
    if ~any(valid)
        warning("Sheet %s: corr_hat is all NaN, skipped.", sh);
        continue;
    end
    i1 = find(valid, 1, "first");
    i2 = find(valid, 1, "last");

    dt_plot = dt(i1:i2);
    y_plot  = y(i1:i2);

    %% --- Plot ---
    fig = figure("Visible","off","Color","w");
    plot(dt_plot, y_plot, "LineWidth", 1.1);
    grid on;

    ax = gca;
    ax.FontSize = 12;
    ax.LineWidth = 0.7;

    % Start/end exactly at data
    xlim([dt_plot(1), dt_plot(end)]);

    % X ticks every 2 years, within the visible range
    y0 = year(dt_plot(1));
    y1 = year(dt_plot(end));
    tickYears = (ceil(y0/XTICK_STEP_YEARS)*XTICK_STEP_YEARS):XTICK_STEP_YEARS:y1;
    if ~isempty(tickYears)
        xticks(datetime(tickYears,1,1));
    end
    xtickformat("yyyy");

    xlabel("Date");
    ylabel("Risk-neutral correlation " + formatPair(leg1) + " and " + formatPair(leg2));
    title(baseQuoteName, "Interpreter","none");

    % --- Readability-first y-limits ---
    yc = y_plot(isfinite(y_plot));
    if numel(yc) >= 10
        lo = prctile(yc, P_LO);
        hi = prctile(yc, P_HI);

        if (hi - lo) < MIN_SPAN
            mid = 0.5*(hi + lo);
            lo = mid - 0.5*MIN_SPAN;
            hi = mid + 0.5*MIN_SPAN;
        end

        pad = PAD_FRAC * (hi - lo);
        lo = lo - pad;
        hi = hi + pad;

        lo = max(Y_VIS_MIN, lo);
        hi = min(Y_VIS_MAX, hi);

        lo = floor(lo / YTICK_STEP) * YTICK_STEP;
        hi = ceil(hi  / YTICK_STEP) * YTICK_STEP;

        if hi <= lo
            lo = max(Y_VIS_MIN, lo - YTICK_STEP);
            hi = min(Y_VIS_MAX, hi + YTICK_STEP);
        end

        ylim([lo, hi]);
        yticks(lo:YTICK_STEP:hi);
    else
        ylim([Y_VIS_MIN, Y_VIS_MAX]);
        yticks(Y_VIS_MIN:YTICK_STEP:Y_VIS_MAX);
    end

    %% --- Save ---
    safeName = regexprep(string(baseQuoteName), '[\\/:*?"<>| ]', '_');
    outPng = fullfile(outDir, safeName + "_corr_hat.png");
    saveas(fig, outPng);
    close(fig);

    fprintf("Saved: %s\n", outPng);
end

fprintf("Done. Saved plots to:\n%s\n", outDir);

%% ===================== Helpers =====================
function [leg1, leg2] = inferLegsFromVars(varNames)
    v = string(varNames);
    vars = v(startsWith(v, "var_") & ~startsWith(v, "integrated_var_"));
    if numel(vars) < 2
        leg1 = "LEG1"; leg2 = "LEG2"; return;
    end
    leg1 = erase(vars(1), "var_");
    leg2 = erase(vars(2), "var_");
end

function s = formatPair(pairStr)
    p = char(pairStr);
    if numel(p) == 6
        s = string(p(1:3)) + "/" + string(p(4:6));
    else
        s = string(pairStr);
    end
end

function name = buildCorrNameFromLegs(leg1, leg2)
% Build filename stem <BASE1><BASE2>_<QUOTE> from two FX legs (6-letter each).
% Example: EURJPY and USDJPY -> EURUSD_JPY

    [b1, q1] = splitPair6(leg1);
    [b2, q2] = splitPair6(leg2);

    % If we can't parse or quotes differ, fall back
    if strlength(q1)==0 || strlength(q2)==0 || q1 ~= q2
        name = string(leg1) + "_" + string(leg2);
        return;
    end

    quote = q1;
    bases = [b1, b2];

    % Put USD second if present (EURUSD, GBPUSD, etc.)
    if any(bases == "USD") && ~all(bases == "USD")
        bases = [bases(bases ~= "USD"), "USD"];
    else
        bases = sort(bases);
    end

    name = bases(1) + bases(2) + "_" + quote;
end

function [base, quote] = splitPair6(pairStr)
    p = string(pairStr);
    if strlength(p) == 6
        base  = extractBetween(p, 1, 3);  base  = base(1);
        quote = extractBetween(p, 4, 6);  quote = quote(1);
    else
        base = p;
        quote = "";
    end
end
