%% view_results_graph_labels_exact.m
% Export Results to Excel using the EXACT pair labels used in the thesis graphs.
%
% This is a pure relabeling/export step: it does NOT change the data.
% It only changes the Excel sheet names (and the INDEX sheet labels).
%
% Graph labels used in the report:
%   EURGBP  -> EURGBP_USD
%   EURJPY  -> EURUSD_JPY
%   EURCHF  -> EURUSD_CHF
%   EURAUD  -> AUDEUR_USD
%   EURCAD  -> EURUSD_CAD
%   GBPJPY  -> GBPUSD_JPY
%   GBPAUD  -> GBPAUD_USD
%   AUDJPY  -> AUDUSD_JPY
%   CADJPY  -> CADUSD_JPY

clear; clc;

%% ------------------------------------------------------------------------
% 1) Paths
% -------------------------------------------------------------------------
base_path = fullfile(getenv("HOME"), "Library", "CloudStorage", "Dropbox", ...
    "2026 Bachelor Thesis", "Empirical Application updated");

% Choose whether to overwrite the existing workbook or create a new one.
overwriteExisting = false;

if overwriteExisting
    outXlsx = fullfile(base_path, "Results_ALL_updated.xlsx");
else
    outXlsx = fullfile(base_path, "Results_ALL_graph_labels.xlsx");
end

%% ------------------------------------------------------------------------
% 2) Load Results (from workspace or .mat file)
% -------------------------------------------------------------------------
if ~exist("Results", "var")
    matFile = fullfile(base_path, "exchange_correlation_ALL.mat");
    if exist(matFile, "file")
        S = load(matFile, "Results");
        if ~isfield(S, "Results")
            error('File "%s" does not contain a variable named Results.', matFile);
        end
        Results = S.Results;
    else
        error("Results not found in workspace and %s was not found.", matFile);
    end
end

names = string(fieldnames(Results));
if isempty(names)
    error("Results is empty.");
end

%% ------------------------------------------------------------------------
% 3) Build exact graph labels
% -------------------------------------------------------------------------
sheetNames = strings(numel(names),1);
idxRows    = NaN(numel(names),1);
idxStart   = NaT(numel(names),1);
idxEnd     = NaT(numel(names),1);

for i = 1:numel(names)
    tri = names(i);
    T   = Results.(char(tri));

    sheetNames(i) = graphLabelFromTriangle(tri);
    idxRows(i)    = height(T);

    if height(T) > 0 && any(strcmp(T.Properties.VariableNames, "date"))
        d = datetime(T.date);
        d = sort(d);
        idxStart(i) = d(1);
        idxEnd(i)   = d(end);
    end
end

% Safety check: all sheet names must be unique
if numel(unique(sheetNames)) ~= numel(sheetNames)
    error("The graph-style sheet labels are not unique. Check the mapping function.");
end

%% ------------------------------------------------------------------------
% 4) Write INDEX sheet
% -------------------------------------------------------------------------
Index = table(names, sheetNames, idxRows, idxStart, idxEnd, ...
    'VariableNames', {'triangle','graph_label','n_rows','start_date','end_date'});

writetable(Index, outXlsx, "Sheet", "INDEX");

%% ------------------------------------------------------------------------
% 5) Write one sheet per triangle using the graph labels
% -------------------------------------------------------------------------
for i = 1:numel(names)
    tri = names(i);
    T   = Results.(char(tri));
    sh  = sheetNames(i);

    writetable(T, outXlsx, "Sheet", char(sh));
end

fprintf("Saved Excel file: %s\n", outXlsx);

%% ========================================================================
% Helper: exact graph label used in the thesis figures
% ========================================================================
function sh = graphLabelFromTriangle(triName)
    triName = string(triName);

    switch triName
        case "EURGBP"
            sh = "EURGBP_USD";
        case "EURJPY"
            sh = "EURUSD_JPY";
        case "EURCHF"
            sh = "EURUSD_CHF";
        case "EURAUD"
            sh = "AUDEUR_USD";
        case "EURCAD"
            sh = "EURUSD_CAD";
        case "GBPJPY"
            sh = "GBPUSD_JPY";
        case "GBPAUD"
            sh = "GBPAUD_USD";
        case "AUDJPY"
            sh = "AUDUSD_JPY";
        case "CADJPY"
            sh = "CADUSD_JPY";
        otherwise
            error("No graph-label mapping defined for triangle '%s'.", triName);
    end

    % Excel sheet names cannot exceed 31 characters
    if strlength(sh) > 31
        error("Sheet name '%s' is too long for Excel.", sh);
    end
end
