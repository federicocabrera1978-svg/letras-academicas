# vendor/

Copias locales (byte a byte) de las dependencias que antes se cargaban desde cdn.jsdelivr.net,
para que la CSP no tenga que permitir un CDN de terceros (`script-src 'self'`).
Los hashes SRI son los mismos que usaba `index.html` y se verificaron el 2026-11-10 contra el CDN.

| Archivo | Origen | SRI (sha384) | Licencia |
|---|---|---|---|
| purify-3.4.17.min.js | npm `dompurify@3.4.17` dist/purify.min.js | P0JNneQf81HOl9VwNXK76cQ9VMD6Nfsnepxb0cCOg8+UzEdzgPHAPV4wVQrvYQSx | Apache-2.0 / MPL-2.0 |
| supabase-js-2.118.0.min.js | npm `@supabase/supabase-js@2.118.0` dist/umd/supabase.min.js | UagCvVPT5XXA0Hx+nJYUAGBFseHT9zBgpJMSebsAxl9lciTwbT+39j5VfRjdP5Tp | MIT |
| quill-2.0.3.js | npm `quill@2.0.3` dist/quill.js | utBUCeG4SYaCm4m7GQZYr8Hy8Fpy3V4KGjBZaf4WTKOcwhCYpt/0PfeEe3HNlwx8 | BSD-3-Clause |
| quill-2.0.3.snow.css | npm `quill@2.0.3` dist/quill.snow.css | ecIckRi4QlKYya/FQUbBUjS4qp65jF/J87Guw5uzTbO1C1Jfa/6kYmd6dXUF6D7i | BSD-3-Clause |
| google.svg | devicons/devicon icons/google/google-original.svg | — | MIT |

Para actualizar una versión: descargarla, calcular
`openssl dgst -sha384 -binary ARCHIVO | openssl base64 -A`, renombrar con la versión y
actualizar `src`/`integrity` en `index.html`.
