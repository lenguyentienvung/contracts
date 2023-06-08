module.exports = {
    ...require('@awuxtron/prettier-config'),
    plugins: [require('prettier-plugin-solidity')],
    bracketSpacing: true,
    overrides: [
        {
            files: '*.sol',
            options: {
                parser: 'solidity-parse',
                singleQuote: false,
                bracketSpacing: true,
            },
        },
    ],
}
