# FileNameSEO - a no-install Windows file renamer
# Renames filenames only: file contents and filename extensions are never changed.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:UndoPath = Join-Path $env:LOCALAPPDATA 'FileNameSEO\last-renames.json'
$script:Preview = @()

function ConvertTo-Slug([string]$Text) {
    $value = $Text.Trim().ToLowerInvariant()
    $value = $value -replace '[\\/:*?"<>|]', ''
    $value = $value -replace '[^\p{L}\p{N}\s_-]', ''
    $value = $value -replace '[\s_]+', '-'
    $value = $value -replace '-+', '-'
    return $value.Trim('-')
}

function Get-TargetName($file, [int]$number) {
    $ext = $file.Extension
    if ($radioPrefix.Checked) {
        $prefix = ConvertTo-Slug $txtPrefix.Text
        if ([string]::IsNullOrWhiteSpace($prefix)) { throw 'SEO 키워드(접두어)를 입력해 주세요.' }
        return ('{0}-{1:D2}{2}' -f $prefix, $number, $ext.ToLowerInvariant())
    }
    $slug = ConvertTo-Slug $file.BaseName
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'file' }
    return $slug + $ext.ToLowerInvariant()
}

function Get-UniqueName($directory, $proposed, $reserved) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($proposed)
    $extension = [IO.Path]::GetExtension($proposed)
    $candidate = $proposed; $n = 2
    while ((Test-Path -LiteralPath (Join-Path $directory $candidate)) -or $reserved.ContainsKey((Join-Path $directory $candidate).ToLowerInvariant())) {
        $candidate = ('{0}-{1:D2}{2}' -f $stem, $n, $extension); $n++
    }
    $reserved[(Join-Path $directory $candidate).ToLowerInvariant()] = $true
    return $candidate
}

function Set-Preview {
    $grid.Rows.Clear(); $script:Preview = @()
    $folder = $txtFolder.Text
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { $lblStatus.Text = '먼저 유효한 폴더를 선택해 주세요.'; return }
    try {
        $files = if ($chkRecursive.Checked) { @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction Stop) } else { @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop) }
        $reserved = @{}; $i = 1
        foreach ($file in $files) {
            $proposed = Get-TargetName $file $i
            $newName = Get-UniqueName $file.DirectoryName $proposed $reserved
            $change = [PSCustomObject]@{ OldPath=$file.FullName; NewName=$newName; OldName=$file.Name }
            $script:Preview += $change
            [void]$grid.Rows.Add($file.DirectoryName, $file.Name, $newName)
            $i++
        }
        $lblStatus.Text = "$($script:Preview.Count)개 파일을 확인했습니다. 표를 검토한 뒤 이름 변경을 누르세요."
    } catch { $lblStatus.Text = "미리보기를 만들지 못했습니다: $($_.Exception.Message)" }
}

function Invoke-Rename {
    if ($script:Preview.Count -eq 0) { [Windows.Forms.MessageBox]::Show('먼저 미리보기를 만들어 주세요.'); return }
    $answer = [Windows.Forms.MessageBox]::Show("$($script:Preview.Count)개 파일의 이름을 변경할까요?`,n파일 확장자와 내용은 유지됩니다.", '최종 확인', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    $completed = @()
    try {
        foreach ($item in $script:Preview) {
            $newPath = Join-Path (Split-Path -LiteralPath $item.OldPath) $item.NewName
            if ($item.OldPath -ne $newPath) {
                Rename-Item -LiteralPath $item.OldPath -NewName $item.NewName -ErrorAction Stop
                $completed += [PSCustomObject]@{ OldPath=$item.OldPath; NewPath=$newPath }
            }
        }
        $undoDirectory = Split-Path -LiteralPath $script:UndoPath
        New-Item -ItemType Directory -Force -Path $undoDirectory | Out-Null
        $completed | ConvertTo-Json | Set-Content -LiteralPath $script:UndoPath -Encoding UTF8
        $lblStatus.Text = "$($completed.Count)개 파일의 이름을 변경했습니다. '마지막 변경 되돌리기'를 사용할 수 있습니다."
        $grid.Rows.Clear(); $script:Preview = @()
    } catch {
        $lblStatus.Text = "일부 변경 후 오류가 발생했습니다: $($_.Exception.Message)"
        if ($completed.Count) { $completed | ConvertTo-Json | Set-Content -LiteralPath $script:UndoPath -Encoding UTF8 }
    }
}

function Undo-LastRename {
    if (-not (Test-Path -LiteralPath $script:UndoPath)) { [Windows.Forms.MessageBox]::Show('되돌릴 최근 변경 기록이 없습니다.'); return }
    try {
        $items = @(Get-Content -LiteralPath $script:UndoPath -Raw | ConvertFrom-Json)
        $answer = [Windows.Forms.MessageBox]::Show("최근 변경 $($items.Count)건을 되돌릴까요?", '되돌리기 확인', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        $reversed = 0
        foreach ($item in $items) {
            if ((Test-Path -LiteralPath $item.NewPath) -and -not (Test-Path -LiteralPath $item.OldPath)) {
                Rename-Item -LiteralPath $item.NewPath -NewName ([IO.Path]::GetFileName($item.OldPath)) -ErrorAction Stop; $reversed++
            }
        }
        Remove-Item -LiteralPath $script:UndoPath -Force
        $lblStatus.Text = "$reversed건을 되돌렸습니다."
    } catch { $lblStatus.Text = "되돌리지 못했습니다: $($_.Exception.Message)" }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'FileNameSEO — 안전한 일괄 파일명 변경'
$form.Size = New-Object Drawing.Size(1000, 680)
$form.StartPosition = 'CenterScreen'; $form.MinimumSize = New-Object Drawing.Size(820, 520)
$form.Font = New-Object Drawing.Font('Malgun Gothic', 9)

$lblFolder = New-Object Windows.Forms.Label -Property @{ Text='대상 폴더'; Location=New-Object Drawing.Point(18,20); AutoSize=$true }
$txtFolder = New-Object Windows.Forms.TextBox -Property @{ Location=New-Object Drawing.Point(90,16); Size=New-Object Drawing.Size(700,25); Anchor='Top,Left,Right' }
$btnBrowse = New-Object Windows.Forms.Button -Property @{ Text='찾아보기'; Location=New-Object Drawing.Point(800,15); Size=New-Object Drawing.Size(95,27); Anchor='Top,Right' }
$folderDialog = New-Object Windows.Forms.FolderBrowserDialog
$btnBrowse.Add_Click({ if ($folderDialog.ShowDialog() -eq 'OK') { $txtFolder.Text=$folderDialog.SelectedPath; Set-Preview } })

$radioSlug = New-Object Windows.Forms.RadioButton -Property @{ Text='기존 파일명을 SEO 형식으로 정리 (공백→하이픈, 소문자)'; Location=New-Object Drawing.Point(18,62); AutoSize=$true; Checked=$true }
$radioPrefix = New-Object Windows.Forms.RadioButton -Property @{ Text='SEO 키워드로 새 이름 만들기'; Location=New-Object Drawing.Point(18,92); AutoSize=$true }
$txtPrefix = New-Object Windows.Forms.TextBox -Property @{ Location=New-Object Drawing.Point(230,89); Size=New-Object Drawing.Size(320,25); Enabled=$false }
$hint = New-Object Windows.Forms.Label -Property @{ Text='예: seoul-korean-bbq → seoul-korean-bbq-01.jpg'; Location=New-Object Drawing.Point(560,93); AutoSize=$true }
$radioSlug.Add_CheckedChanged({ $txtPrefix.Enabled=$radioPrefix.Checked })
$radioPrefix.Add_CheckedChanged({ $txtPrefix.Enabled=$radioPrefix.Checked })
$chkRecursive = New-Object Windows.Forms.CheckBox -Property @{ Text='하위 폴더의 파일도 포함'; Location=New-Object Drawing.Point(18,125); AutoSize=$true }
$btnPreview = New-Object Windows.Forms.Button -Property @{ Text='미리보기 새로고침'; Location=New-Object Drawing.Point(250,120); Size=New-Object Drawing.Size(125,29) }
$btnRename = New-Object Windows.Forms.Button -Property @{ Text='이름 변경 실행'; Location=New-Object Drawing.Point(385,120); Size=New-Object Drawing.Size(115,29); BackColor=[Drawing.Color]::FromArgb(220,240,255) }
$btnUndo = New-Object Windows.Forms.Button -Property @{ Text='마지막 변경 되돌리기'; Location=New-Object Drawing.Point(510,120); Size=New-Object Drawing.Size(145,29) }
$btnPreview.Add_Click({ Set-Preview }); $btnRename.Add_Click({ Invoke-Rename }); $btnUndo.Add_Click({ Undo-LastRename })

$grid = New-Object Windows.Forms.DataGridView
$grid.Location=New-Object Drawing.Point(18,165); $grid.Size=New-Object Drawing.Size(945,420); $grid.Anchor='Top,Bottom,Left,Right'
$grid.ReadOnly=$true; $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false; $grid.AutoSizeColumnsMode='Fill'; $grid.RowHeadersVisible=$false
[void]$grid.Columns.Add('Folder','폴더'); [void]$grid.Columns.Add('Old','현재 파일명'); [void]$grid.Columns.Add('New','변경될 파일명')
$grid.Columns['Folder'].FillWeight=42; $grid.Columns['Old'].FillWeight=29; $grid.Columns['New'].FillWeight=29
$lblStatus = New-Object Windows.Forms.Label -Property @{ Text='폴더를 선택하고 미리보기를 확인해 주세요.'; Location=New-Object Drawing.Point(18,605); Size=New-Object Drawing.Size(945,35); Anchor='Bottom,Left,Right'; ForeColor=[Drawing.Color]::FromArgb(50,50,50) }

$form.Controls.AddRange(@($lblFolder,$txtFolder,$btnBrowse,$radioSlug,$radioPrefix,$txtPrefix,$hint,$chkRecursive,$btnPreview,$btnRename,$btnUndo,$grid,$lblStatus))
[void]$form.ShowDialog()

