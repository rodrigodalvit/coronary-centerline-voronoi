%% generate_synthetic_coronary_vessel_volume.m
% Synthetic coronary vessel volume generation from annotated centerline data.
%
% This script accompanies:
% Dalvit Carvalho da Silva R, Soltanzadeh R, Figley CR.
% Automated Coronary Artery Tracking with a Voronoi-Based 3D Centerline
% Extraction Algorithm. Journal of Imaging. 2023;9(12):268.
% https://doi.org/10.3390/jimaging9120268
%
% Purpose
% -------
% The script creates a synthetic 3D vessel segmentation from a text file
% containing centerline coordinates and radius values in columns:
%
%     x   y   z   radius
%
% The code was designed for the Rotterdam Coronary Artery Algorithm
% Evaluation Framework / CAT08-style annotated centerline format.
%
% Notes
% -----
% - The full Voronoi-based centerline extraction algorithm is not included
%   here because it is protected by intellectual-property and patent-related
%   restrictions.
% - This script documents the shareable synthetic vessel-generation component.
% - The output .mat volume can be large. Saving with -v7.3 is recommended.
%
% Requirements
% ------------
% MATLAB with Image Processing Toolbox.
% Parallel Computing Toolbox is optional; the script runs without it.
%
% Rodrigo Dalvit Carvalho da Silva

clear; close all; clc;

%% User parameters
q = 10;                    % coordinate scaling: 10 = coarse; 1000 = finer but much heavier
sphereResolution = 200;    % sphere mesh resolution used to sample each centerline point
useParallel = true;        % set false to force regular for-loop

%% Load annotated centerline file
% Expected input: *.txt file containing x, y, z, and radius columns.
[file, pathfile] = uigetfile({'*.txt;*.csv;*.*', 'Centerline file (*.txt, *.csv, *.*)'}, ...
                             'Select centerline file with columns x, y, z, radius');

if isequal(file, 0)
    disp('User selected Cancel');
    return;
else
    fullfilename = fullfile(pathfile, file);
    fprintf('User selected: %s\n', fullfilename);
end

referenceIn = load(fullfilename);
reference = referenceIn(:, 1:4);

%% Data rounding / scaling
% Scaling increases coordinate resolution before creating the synthetic volume.
reference = round(q * reference);

%% Data translation
% Translate coordinates so all indices are positive and include enough space
% for the local vessel radius.
reference(:, 1) = reference(:, 1) - min(reference(:, 1)) + max(reference(:, 4)) + 1;
reference(:, 2) = reference(:, 2) - min(reference(:, 2)) + max(reference(:, 4)) + 1;
reference(:, 3) = reference(:, 3) - min(reference(:, 3)) + max(reference(:, 4)) + 1;

r = reference(:, 4);
c = reference(:, 1:3);

%% Sphere creation along the annotated centerline
% A sphere is generated at each annotated centerline point using the local
% radius. The union of these spheres forms the synthetic vessel volume.
[xs, ys, zs] = sphere(sphereResolution);
nPoints = size(c, 1);

Xcell = cell(nPoints, 1);
Ycell = cell(nPoints, 1);
Zcell = cell(nPoints, 1);

canUseParallel = useParallel && license('test', 'Distrib_Computing_Toolbox');

if canUseParallel
    try
        gcp('nocreate'); %#ok<NOPRT>
        parfor ct = 1:nPoints
            Xcell{ct} = reshape(xs * r(ct) + c(ct, 1), [], 1);
            Ycell{ct} = reshape(ys * r(ct) + c(ct, 2), [], 1);
            Zcell{ct} = reshape(zs * r(ct) + c(ct, 3), [], 1);
        end
    catch
        warning('Parallel execution failed. Re-running with a regular for-loop.');
        for ct = 1:nPoints
            Xcell{ct} = reshape(xs * r(ct) + c(ct, 1), [], 1);
            Ycell{ct} = reshape(ys * r(ct) + c(ct, 2), [], 1);
            Zcell{ct} = reshape(zs * r(ct) + c(ct, 3), [], 1);
        end
    end
else
    for ct = 1:nPoints
        Xcell{ct} = reshape(xs * r(ct) + c(ct, 1), [], 1);
        Ycell{ct} = reshape(ys * r(ct) + c(ct, 2), [], 1);
        Zcell{ct} = reshape(zs * r(ct) + c(ct, 3), [], 1);
    end
end

X = vertcat(Xcell{:});
Y = vertcat(Ycell{:});
Z = vertcat(Zcell{:});

% Convert sampled sphere points into voxel coordinates and remove duplicates.
A = unique(uint16(round([X, Y, Z])), 'rows');
A = A(all(A > 0, 2), :);

clear X Y Z Xcell Ycell Zcell xs ys zs

%% Image / volume creation
M = double(max(A, [], 1));
Im = false(M(1), M(2), M(3));

linearIdx = sub2ind(size(Im), double(A(:, 1)), double(A(:, 2)), double(A(:, 3)));
Im(linearIdx) = true;

% Fill holes slice-by-slice.
for k = 1:size(Im, 3)
    Im(:, :, k) = imfill(Im(:, :, k), 'holes');
end

% Pad image volume with zero-valued faces.
Im = padarray(Im, [1 1 1], 0, 'both');

%% Display volume when possible
try
    volshow(Im);
catch
    warning('volshow is unavailable in this MATLAB installation. Skipping volume display.');
end

%% Save NIfTI image and workspace outputs
Ref = [c, r];

[file1, path1] = uiputfile('*.nii', 'Save NIfTI volume as');
[file2, path2] = uiputfile('*.mat', 'Save transformed coordinates as');
[file3, path3] = uiputfile('*.mat', 'Save MATLAB volume as');

if ~isequal(file1, 0)
    filename1 = fullfile(path1, file1);
    niftiwrite(uint8(Im), filename1);
    fprintf('Saved NIfTI volume: %s\n', filename1);
end

if ~isequal(file2, 0)
    filename2 = fullfile(path2, file2);
    save(filename2, 'Ref');
    fprintf('Saved transformed coordinates: %s\n', filename2);
end

if ~isequal(file3, 0)
    filename3 = fullfile(path3, file3);
    save(filename3, 'Im', '-v7.3');
    fprintf('Saved MATLAB volume: %s\n', filename3);
end

fprintf('Synthetic vessel generation complete.\n');
