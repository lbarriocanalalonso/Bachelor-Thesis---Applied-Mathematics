%% joint_crash_probability_smoothed.m
% Exports: one PNG per triangle
% Naming:
%   <CROSSPAIR>_<NUMERAIRE>_joint_crash_smoothed.png


clear; clc; close all;

%% --- Path ---
fileName  = "Results_ALL_updated.xlsx";
excelPath = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated", fileName);

assert(isfile(excelPath), "Cannot find Excel file:\n%s", excelPath);

outDir = fullfile(fileparts(excelPath), "Figure 5 panels ", "fig5 d joint crash probability smoothed");
if ~exist(outDir, "dir"); mkdir(outDir); end

%% --- Choose sheets ---
sheets = sheetnames(excelPath);
sheets = sheets(~strcmpi(sheets, "INDEX"));

%% --- Axis formatting ---
xL     = [datetime(2008,7,1) datetime(2023,4,30)];
xTicks = datetime(2010:2:2022, 1, 1);

yL     = [-0.05 0.25];
yTicks = -0.05:0.05:0.25;

smoothWindow = 30; % "30-day moving average" (30 observations)

%% --- Loop over sheets ---
for i = 1:numel(sheets)
    sh = sheets{i};

    T = readtable(excelPath, "Sheet", sh);

    % Required columns (for risk-neutral + dates)
    if ~ismember("date", string(T.Properties.VariableNames)) || ...
       ~ismember("tail_risk", string(T.Properties.VariableNames))
        warning('Skipping "%s" (missing date and/or tail_risk).', sh);
        continue;
    end

    % Convert date
    d = T.date;
    if ~isdatetime(d)
        if isnumeric(d)
            d = datetime(d, "ConvertFrom", "excel");
        else
            d = datetime(d);
        end
    end

    % Identify the two FX legs from var_* columns (var_EURUSD, var_GBPUSD)
    v = string(T.Properties.VariableNames);
    varCols = v(startsWith(v, "var_") & ~startsWith(v, "integrated_var_"));
    if numel(varCols) < 2
        warning('Skipping "%s" (cannot infer the two FX legs from var_* columns).', sh);
        continue;
    end

    p1 = erase(varCols(1), "var_");
    p2 = erase(varCols(2), "var_");

    ret1Name = "ret_" + p1;
    ret2Name = "ret_" + p2;

    if ~ismember(ret1Name, v) || ~ismember(ret2Name, v)
        warning('Skipping "%s" (missing %s or %s for physical crash).', sh, ret1Name, ret2Name);
        continue;
    end


    % Build filename label like "EURUSD_JPY" (matches volatility/correlation)
    label = triangleLabelFromLegs(p1, p2);
    if strlength(label) == 0
        % fallback: keep sheet name if something unexpected happens
        label = string(sh);
    end

    % Title label: always show CROSSPAIR_NUMERAIRE 
    titleLabel = label;
    if strlength(titleLabel) == 0
        titleLabel = string(sh);   % fallback if something unexpected happens
    end

    % Series
    rn = T.tail_risk;                % risk-neutral dependent crash probability
    r1 = T.(ret1Name);
    r2 = T.(ret2Name);

    crash = double((r1 <= 0.97) & (r2 <= 0.97));  % realized (physical) crash indicator

    % Clean/sort
    ok = ~isnat(d) & isfinite(rn) & isfinite(crash);
    d = d(ok); rn = rn(ok); crash = crash(ok);
    [d, ix] = sort(d);
    rn = rn(ix); crash = crash(ix);

    % Restrict to plot window
    inW = (d >= xL(1)) & (d <= xL(2));
    d = d(inW); rn = rn(inW); crash = crash(inW);

    if isempty(d)
        warning('Skipping "%s" (no data in plot window).', sh);
        continue;
    end

    %% --- OLS to get "physical crash probability estimated from OLS" ---
    X = [ones(size(rn)), rn];
    b = X \ crash;                 % OLS coefficients
    physHat = X * b;               % fitted "physical" crash probability

    %% --- 30-day moving average smoothing ---
    rn_s   = movmean(rn,      smoothWindow, "omitnan");  % centered by default
    phys_s = movmean(physHat, smoothWindow, "omitnan");

    %% --- Plot ---
    fig = figure("Color","w","Units","pixels","Position",[100 100 880 360]);
    ax = axes(fig); hold(ax, "on");

    hPhys = plot(ax, d, phys_s, "LineWidth", 0.9);
    hRN   = plot(ax, d, rn_s,   "LineWidth", 0.9);

    xlim(ax, xL);
    xticks(ax, xTicks);
    xtickformat(ax, "yyyy");

    ylim(ax, yL);
    yticks(ax, yTicks);

    xlabel(ax, "Date");
    ylabel(ax, "Joint probability of crash");

    % Title
    t = title(ax, titleLabel, "FontWeight","normal", "FontSize", 12, "Interpreter","none");
    t.Units = "normalized";
    t.Position(2) = 1.02;

    % Legend
    lgd = legend(ax, [hPhys hRN], {"Physical", "Risk-neutral"}, ...
        "Location","northeast", "Box","on");
    lgd.FontSize = 9;
    lgd.ItemTokenSize = [12 10];
    lgd.EdgeColor = [0 0 0];
    lgd.LineWidth = 0.7;

    ax.Box = "on";
    ax.LineWidth = 0.8;
    ax.FontSize = 10;
    ax.TickDir = "out";
    grid(ax, "off");

    %% --- Export PNG ---
    safeLabel = regexprep(string(label), '[\\/:*?"<>| ]', '_');
    pngPath = fullfile(outDir, safeLabel + ".png");

    if exist("exportgraphics","file") == 2
        exportgraphics(fig, pngPath, "Resolution", 200);
    else
        print(fig, pngPath, "-dpng", "-r200");
    end

    % Optional: show OLS coefficients in console
    fprintf('%s | OLS: crash = %.4f + %.4f * RNprob\n', label, b(1), b(2));

    close(fig);
end

fprintf("Done. Outputs saved in:\n%s\n", outDir);

%% ===== helper: EURUSD -> EUR/USD =====
function out = prettyFX(pair)
    pair = string(pair);
    if strlength(pair) == 6
        out = extractBetween(pair, 1, 3) + "/" + extractBetween(pair, 4, 6);
        out = out(1);
    else
        out = pair;
    end
end

function label = triangleLabelFromLegs(leg1, leg2)
    % leg format: "EURJPY", "USDJPY", etc.
    % numeraire = common quote currency (last 3 chars)
    % crosspair = base currencies (first 3 chars), with rule:
    %   if one base is USD and the other isn't, put non-USD first.

    label = "";
    leg1 = string(leg1); leg2 = string(leg2);

    if strlength(leg1) ~= 6 || strlength(leg2) ~= 6
        return;
    end

    l1 = char(leg1); l2 = char(leg2);
    b1 = string(l1(1:3)); q1 = string(l1(4:6));
    b2 = string(l2(1:3)); q2 = string(l2(4:6));

    if q1 ~= q2
        return;
    end

    numeraire = q1;

    if (b1 == "USD" && b2 ~= "USD")
        a = b2; b = b1;     % non-USD first
    else
        a = b1; b = b2;     % keep original order
    end

    cross = a + b;          % e.g. EUR + USD -> "EURUSD"
    label = cross + "_" + numeraire;
end