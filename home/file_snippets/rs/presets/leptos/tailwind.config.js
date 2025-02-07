/** @type {import('tailwindcss').Config} */
module.exports = {
    darkMode: 'class',
    content: [
        // Rust project-specific paths for Leptos
        "./src/**/*.rs",
        "./index.html",
        "./src/**/*.html",
    ],
    theme: {
        extend: {
            colors: {
                // Custom color palette (optional)
                'brand': {
                    '50': '#f0f9ff',
                    '100': '#e0f2fe',
                    '200': '#bae6fd',
                    '300': '#7dd3fc',
                    '400': '#38bdf8',
                    '500': '#0ea5e9',
                    '600': '#0284c7',
                    '700': '#0369a1',
                    '800': '#075985',
                    '900': '#0c4a6e',
                },
            },
            spacing: {
                // Custom spacing if needed
                '128': '32rem',
                '144': '36rem',
            },
            borderRadius: {
                // Custom border radius
                'xl': '1rem',
                '2xl': '1.5rem',
            },
            fontFamily: {
                // Custom font families
                'sans': ['Inter', 'system-ui', 'sans-serif'],
                'mono': ['Fira Code', 'monospace'],
            },
            animation: {
                // Custom animations
                'spin-slow': 'spin 3s linear infinite',
                'pulse-slow': 'pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
            },
        },
    },
    plugins: [

    ],
    // Disable unused utilities to reduce bundle size
    corePlugins: {
        preflight: true,
    },
};
