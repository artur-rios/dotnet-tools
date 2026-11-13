# PSScriptAnalyzer's settings for ci/lint.sh (the `lint` check): every default rule, except those below. Each one
# flags code that works as intended, and following it would change what the scripts do or rename their functions,
# so it is left off rather than "fixed":
#   PSAvoidUsingWriteHost                       the commands print progress for a person at a terminal, on purpose
#   PSAvoidUsingEmptyCatchBlock                 best-effort cleanup and probes (git tags, jobs) that must not fail
#   PSUseShouldProcessForStateChangingFunctions internal helpers (New-Backup, Remove-DirTree, New-GitTag, ...), not
#                                               cmdlets: -WhatIf/-Confirm would mean nothing
#   PSAvoidAssignmentToAutomaticVariable        bump.ps1 and test.ps1 filter $args on purpose (the wrapper's token)
#   PSAvoidOverwritingBuiltInCmdlets            bump.ps1 defines its own Write-Log helper: renaming it is not a lint fix
#   PSUseSingularNouns                          Get-Flags, Remove-GitTagIfExists: the same
@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSAvoidOverwritingBuiltInCmdlets',
        'PSUseSingularNouns'
    )
}
