
filename = "C:\Users\Andreas\Downloads\dirty_cafe_sales-1.csv";
% or place the CSV in the current folder and keep the same name

T = readtable(filename, "VariableNamingRule", "preserve");

% Find columns even if the headers have spaces or different casing
itemName = getVarName(T, "Item");
qtyName = getVarName(T, "Quantity");
priceName = getVarName(T, "Price Per Unit");
totalName = getVarName(T, "Total Spent");
paymentName = getVarName(T, "Payment Method");

% Treat missing/invalid values in ALL columns:
% every text column -> ERROR / UNKNOWN / blanks become <missing>
numericCols = [qtyName, priceName, totalName];
allVars = string(T.Properties.VariableNames);
for c = allVars
    if ~ismember(c, numericCols) && ~isnumeric(T.(c)) && ~isdatetime(T.(c))
        T.(c) = cleanLabel(T.(c));
    end
end
% date columns -> datetime (invalid dates become NaT)
for c = allVars(contains(lower(allVars), "date"))
    if ~isdatetime(T.(c))
        T.(c) = datetime(T.(c), "InputFormat", "yyyy-MM-dd");
    end
end

% Convert numeric fields (invalid text -> NaN)
quantity = toNumeric(T.(qtyName));
price = toNumeric(T.(priceName));
totalSpent = toNumeric(T.(totalName));

% Recover missing Quantity / Price from the other two values
idx = isnan(quantity) & ~isnan(totalSpent) & price > 0;
quantity(idx) = round(totalSpent(idx) ./ price(idx));
idx = isnan(price) & ~isnan(totalSpent) & quantity > 0;
price(idx) = totalSpent(idx) ./ quantity(idx);

% Fill remaining missing prices with each item's standard (median) price
item0 = T.(itemName);
known = ~ismissing(item0) & ~isnan(price);
[names0, ~, g] = unique(item0(known));
stdPrice = accumarray(g, price(known), [], @median);
idx = find(isnan(price) & ~ismissing(item0));
[tf, loc] = ismember(item0(idx), names0);
price(idx(tf)) = stdPrice(loc(tf));

% Recalculate Total Spent when missing or inconsistent
recalcTotal = quantity .* price;
tol = 1e-6;
needsUpdate = isnan(totalSpent) | ...
    (isfinite(recalcTotal) & abs(totalSpent - recalcTotal) > tol .* max(1, abs(recalcTotal)));
totalSpent(needsUpdate & ~isnan(recalcTotal)) = recalcTotal(needsUpdate & ~isnan(recalcTotal));

% Write cleaned numeric values back
T.(qtyName) = quantity;
T.(priceName) = price;
T.(totalName) = totalSpent;

% Keep only rows with Total Spent available after cleaning
Tclean = T(~isnan(T.(totalName)), :);

% Summary statistics for Total Spent
x = Tclean.(totalName);
statsTable = table( ...
    sum(~isnan(x)), ...
    mean(x, "omitnan"), ...
    std(x, "omitnan"), ...
    min(x, [], "omitnan"), ...
    median(x, "omitnan"), ...
    max(x, [], "omitnan"), ...
    sum(x, "omitnan"), ...
    'VariableNames', ["Count","Mean","StdDev","Min","Median","Max","Sum"]);
disp(statsTable)

% Item and payment analysis
item = Tclean.(itemName);
payment = Tclean.(paymentName);
qty = Tclean.(qtyName);

validItem = ~ismissing(item);
validPayment = ~ismissing(payment);

% Group with string unique (missing values already removed, so no stray groups)
[itemNames, ~, itemIdx] = unique(item(validItem));
itemTxnCounts = accumarray(itemIdx, 1);
itemRevenue = accumarray(itemIdx, x(validItem), [], @(v) sum(v, "omitnan"));
itemQtyTotals = accumarray(itemIdx, qty(validItem), [], @(v) sum(v, "omitnan"));

[~, iTxnMax] = max(itemTxnCounts);
[~, iQtyMax] = max(itemQtyTotals);
mostFrequentItem = itemNames(iTxnMax);
highestQuantityItem = itemNames(iQtyMax);

[paymentNames, ~, paymentIdx] = unique(payment(validPayment));
paymentCounts = accumarray(paymentIdx, 1);
[~, iPayMax] = max(paymentCounts);
mostPreferredPayment = paymentNames(iPayMax);

fprintf("Most frequent item by transactions: %s\n", mostFrequentItem);
fprintf("Item with greatest total quantity: %s\n", highestQuantityItem);
fprintf("Most preferred payment method: %s\n", mostPreferredPayment);

% Bar chart: Total revenue per item
plotSortedBarh(itemNames, itemRevenue, "Total Revenue per Item", ...
    "Total Revenue ($)", "  $%.2f");

% Bar chart: Transactions per item
plotSortedBarh(itemNames, itemTxnCounts, "Transactions per Item", ...
    "Number of Transactions", "  %d");

% Pie chart: Payment methods (one distinct color per slice)
[paymentCounts, ordPay] = sort(paymentCounts, "descend");
paymentNames = paymentNames(ordPay);
pct = 100 * paymentCounts / sum(paymentCounts);
pieLabels = compose("%s\n%.1f%%", paymentNames, pct);

figure("Position", [100 100 700 550], "Color", "w");
h = pie(paymentCounts, cellstr(pieLabels));
slices = h(1:2:end);          % pie returns [patch, text, patch, text, ...]
sliceText = h(2:2:end);
colors = lines(numel(slices)); % distinct, high-contrast colors
for k = 1:numel(slices)
    slices(k).FaceColor = colors(k, :);
    slices(k).EdgeColor = "w";
    slices(k).LineWidth = 1.5;
    sliceText(k).FontSize = 12;
end
title("Payment Method Share", "FontSize", 14);

% Histogram of Total Spent
figure("Position", [100 100 900 500], "Color", "w");
histogram(x, "BinWidth", 1, "FaceColor", [0.2 0.45 0.75], "EdgeColor", "w");
xlabel("Total Spent ($)");
ylabel("Frequency");
title("Distribution of Total Spent");
set(gca, "FontSize", 12);
grid on;

%% ---------- Local functions ----------

function varName = getVarName(T, target)
vars = string(T.Properties.VariableNames);
normVars = lower(regexprep(vars, "[^a-zA-Z0-9]", ""));
normTarget = lower(regexprep(string(target), "[^a-zA-Z0-9]", ""));
idx = find(normVars == normTarget, 1);
if isempty(idx)
    error('Could not find a column matching "%s".', target);
end
varName = vars(idx);
end

function x = toNumeric(v)
if isnumeric(v)
    x = double(v);
    return
end
s = string(v);
s = strtrim(s);
s = regexprep(s, ",", "");
s = regexprep(s, "[^\d\.\-\+eE]", "");
x = str2double(s);
end

function s = cleanLabel(v)
% Turn placeholder text and blanks into <missing> so they are not plotted as categories
s = strtrim(string(v));
bad = ["", "ERROR", "UNKNOWN", "NA", "N/A", "NAN", "NULL", "NONE"];
s(ismissing(s) | ismember(upper(s), bad)) = missing;
end

function plotSortedBarh(names, values, ttl, xlab, fmt)
% Horizontal bars: labels get their own space instead of being squeezed under bars
[values, o] = sort(values, "ascend");   % ascending so the largest bar ends up on top
names = names(o);
n = numel(values);

figure("Position", [100 100 900 max(350, 45*n + 120)], "Color", "w");
b = barh(values, 0.7, "FaceColor", "flat");
b.CData = repmat([0.2 0.45 0.75], n, 1);
b.CData(end, :) = [0.85 0.33 0.10];     % highlight the top item

yticks(1:n);
yticklabels(names);
xlim([0, max(values) * 1.15]);          % room for the value labels
text(values, 1:n, compose(fmt, values), ...
    "VerticalAlignment", "middle", "FontSize", 11);

xlabel(xlab);
title(ttl, "FontSize", 14);
set(gca, "FontSize", 12, "TickLength", [0 0]);
grid on;
box off;
end