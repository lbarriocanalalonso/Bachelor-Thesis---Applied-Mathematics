%% joint_crash_probability.m 
%   Independent = marginal_hat_1 .* marginal_hat_2
%   Dependent   = tail_risk
% Exports: one PNG per triangle.
%   Figure5c_<CROSSPAIR>_<NUMERAIRE>.png

clear; clc; close all;

%% --- Paths ---
fileName  = "Results_ALL_updated.xlsx";
excelPath = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated", fileName);

assert(isfile(excelPath), "Unable to find or open:\n%s", excelPath);

outDir = fullfile(fileparts(excelPath), "Figure5c_outputs");
if ~exist(outDir, "dir"); mkdir(outDir); end

%% --- Sheets ---
sheets = sheetnames(excelPath);
sheets = sheets(~strcmpi(sheets, "INDEX"));

%% --- Axis formatting ---
xL     = [datetime(2008,1,1) datetime(2024,3,31)];
xTicks = datetime(2010:2:2022, 1, 1);

yL     = [-0.05 0.30];
yTicks = -0.05:0.05:0.30;

%% --- Loop ---
for i = 1:numel(sheets)
    sh = sheets{i};

    T = readtable(excelPath, "Sheet", sh, "PreserveVariableNames", true);

    % Required columns
    req = ["date","tail_risk","marginal_hat_1","marginal_hat_2"];
    if ~all(ismember(req, string(T.Properties.VariableNames)))
        warning('Skipping "%s" (missing required columns).', sh);
        continue;
    end

    % Date conversion
    d = parseDateRobust(T.date);
    if all(isnat(d))
        warning('Skipping "%s" (could not parse dates).', sh);
        continue;
    end

    dep = T.tail_risk;
    ind = T.marginal_hat_1 .* T.marginal_hat_2;

    % Clean/sort/filter to plot window
    ok = isfinite(dep) & isfinite(ind) & ~isnat(d);
    d = d(ok); dep = dep(ok); ind = ind(ok);

    [d, ix] = sort(d);
    dep = dep(ix); ind = ind(ix);

    inWindow = (d >= xL(1)) & (d <= xL(2));
    d = d(inWindow); dep = dep(inWindow); ind = ind(inWindow);

    if isempty(d)
        warning('Skipping "%s" (no data in plot window).', sh);
        continue;
    end

    % ---- Infer legs from var_* columns  ----
    % We use var_ columns because they contain the legs used for the projection.
    v = string(T.Properties.VariableNames);
    varCols = v(startsWith(v,"var_") & ~startsWith(v,"integrated_var_"));

    leg1 = ""; leg2 = "";
    if numel(varCols) >= 2
        leg1 = erase(varCols(1), "var_");
        leg2 = erase(varCols(2), "var_");
    end

    % Build triangle label using the same rule as volatility:
    %   <CROSSPAIR>_<NUMERAIRE> with non-USD first when applicable
    label = triangleLabelFromLegs(leg1, leg2);
    if strlength(label) == 0
        % fallback: keep sheet name if something unexpected happens
        label = string(sh);
    end

    % Title label: always show CROSSPAIR_NUMERAIRE (same as volatility naming)
    titleLabel = label;
    if strlength(titleLabel) == 0
        titleLabel = string(sh);   % fallback if something unexpected happens
    end

    %% --- Plot ---
    fig = figure("Color","w","Units","pixels","Position",[100 100 880 360]);
    ax = axes(fig); hold(ax,"on");

    hInd = plot(ax, d, ind, "LineWidth", 0.9);
    hDep = plot(ax, d, dep, "LineWidth", 0.9);

    xlim(ax, xL);
    xticks(ax, xTicks);
    xtickformat(ax, "yyyy");

    ylim(ax, yL);
    yticks(ax, yTicks);

    xlabel(ax, "Date");
    ylabel(ax, "Joint probability of crash");

    t = title(ax, titleLabel, "FontWeight","normal", "FontSize", 12, "Interpreter","none");
    t.Units = "normalized";
    t.Position(2) = 1.02;

    lgd = legend(ax, [hInd hDep], {"Independent","Dependent"}, ...
        "Location","northeast", "Box","on");
    lgd.FontSize = 9;
    lgd.ItemTokenSize = [12 10];
    lgd.Color = "white";
    lgd.EdgeColor = [0 0 0];
    lgd.LineWidth = 0.7;

    ax.Box = "on";
    ax.LineWidth = 0.8;
    ax.FontSize = 10;
    ax.TickDir = "out";
    grid(ax, "off");

    %% --- Export  ---
    safeLabel = regexprep(label, '[\\/:*?"<>| ]', '_');

    pngPath = fullfile(outDir, "Figure5c_" + safeLabel + ".png");

    if exist("exportgraphics","file") == 2
        exportgraphics(fig, pngPath, "Resolution", 200);
    else
        print(fig, pngPath, "-dpng", "-r200");
    end

    close(fig);
end

fprintf("Done.\nOutputs saved in:\n%s\n", outDir);

%% -------------------- helper functions --------------------

function label = triangleLabelFromLegs(leg1, leg2)
    % leg format: "EURJPY", "USDJPY", etc.
    % numeraire = common quote currency (last 3 chars)
    % crosspair = base currencies (first 3 chars), with rule:
    %   if one base is USD and the other isn't, put non-USD first.

    label = "";
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

function s = formatPair(pairStr)
    p = char(pairStr);
    if numel(p) == 6
        s = string(p(1:3)) + "/" + string(p(4:6));
    else
        s = string(pairStr);
    end
end

function dt = parseDateRobust(x)
    if isdatetime(x)
        dt = x;
        return;
    end
    if isnumeric(x)
        try
            dt = datetime(x, "ConvertFrom", "excel");
            return;
        catch
            dt = NaT(size(x));
            return;
        end
    end
    if iscell(x); x = string(x); else; x = string(x); end

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

    try
        tmp = datetime(x);
        mask = isnat(dt) & ~isnat(tmp);
        dt(mask) = tmp(mask);
    catch
    end
end