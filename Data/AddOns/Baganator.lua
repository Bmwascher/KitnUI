-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Baganator.lua                                               ║
-- ║  Purpose: Profile data: the raw Baganator profile export     ║
-- ║           string.                                            ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- Written into a named BAGANATOR_CONFIG.Profiles entry on import and activated
-- for this character through BAGANATOR_CURRENT_PROFILE, which is a per-character
-- SavedVariable. Applied only on an explicit install or load action, never on
-- PLAYER_LOGIN, so changes the user makes inside the profile survive a reload.
--
-- HOW TO UPDATE: in game, open Baganator > Customise, click Export on the
-- GENERAL page (not the Categories page), and paste the whole string below.
-- That one string is the entire profile, categories included; the separate
-- Categories export is a subset and is not used here.
--
-- The format is Baganator's own: "BGR!1!" followed by base64 of a deflated
-- CBOR table (CustomiseDialog/Main.lua:758). Setup.lua decodes it with
-- C_EncodingUtil and writes the result straight into the profile. Baganator
-- exported plain JSON until 2026; the old categoriesJSON field is gone.
ns.data.Baganator = {
    profileString = [[BGR!1!rVhLbxvJEaZjBMhh4VwlL9YwIOS4MOfFIfeyHpkSqRcl0bTE26A10yQ7nJe7eyTTyEHJJv9hLzlorQRIkFwCBNhjgPyE/IgAOc9cvAiS6u6ZIUXJjmiEp2F11/vrqq7+fnA0Tkngu+cEX7gXxOeTR/0IPgnHIXNHAWITEo3zHsV+6mGXJciD/9nBGRorHj5LcNdDHI9jOhs+RimPQ8SJ5xY0gpmLfB/7l4dsEl+4DCPqTdyz+E1+6uOzdLy4US1mw7UzFE2VfMkktLEg5iw7nK9Ia9fW9lhMuRtiPon9trBmuE7xOaYMu2MapwlIFRti6mOa7Qj73DjB0Z93OUU+ZlMSBNm+cNdNk7Eg5bsqJEJT1g0xWIQinvdGMR1jNx6B7ZHPsgOUepzEkTuJU4bzQ9hFkccxdRMU4SA7Zh5FSQLRckPkQRRxfiTVkAg2Icmbt0NEgqzDYm+KwbsDaRMIoDwCa9vChHz4lHigxosp0CCYwgMSMQxOgfyAYP/d0RniPABGzN0AnA/y3hTPGI8jXPzvihCK6OSnVeqWQ1tm0Z0QSFh05dh5X6oOEZ26aZQydBbg7ETSJDRcRkISIOqigGfD9UoA9gkvMx3GPt4+JyxFwcvCEQjAG+6OkC+g9fICUfDTd72UUhxxl6Oz2kklSoZMJlJsHj6WInicgF8jXgTFRZSi2a/bP0+j6a1QLEViVwpUKxR7UiEJcZzyn86V+oQlAZop0Hy7MfDxCKUBV7FXXKz9Jfw2XW1Tqzut/XLHKI59p9kv/4KxLA1F2LZcF0f+pqs7jb1ydYzD4ec3ZOPXKUlCYRQDPPTKtQuMkjg6qLbSMKaOXYo0jsqF0tXjkvA6xYwLj1+VlJAwDwcBQBRgu7fAWPGoAEL8jhe84AgATA9LisA85KO0wKwWKEZjML8KgAT0GIIydwbiR5IiHpVLMZ9gKkNahVJkszKbJcCFAheHCZ9tQUGJo51NNEYR4jHdL6EDpznqngXk7VtE/T7AGMNhhTMrQBeGcZT15uXjRuHqSViNKZ5JtdmggsJydRlIAuNIHD8IVsyh4GXDzytcUjKe3ATm5fCJXFV779jwy+7rFEoM4bP+3L4kZkTUiG92Nw8Hg8OD/a3twfvNb2ufvd/87X/+PSiwSyIvSMHN+CLCfvZqoZiX/K7+TWdweCTY1540/3U89wzLGsSuHe2qHaEQ724xBjIhzMwxFan7ou9sD3Z6HcdQhJ0XiHuTL50gcHRFaXfgnO8zjCOAaQBxxg9OZOTLlFXouTwRxUZmUDYSLAIIIcuGX8xLDzSCt4IhKHuNq//w9T8M+WtDev1OQuMRCfDp/LQWGCFhArlZf/jPo+XGkg0fz8uzDPFCsXnQEd0CIvHw2EuZyNCc8Y+O9p0KxFYk2wDbVmXteEOcqqc4AqKHxYl1jGLnKdSzOI38YudzR1cLnVecBJDjgt7dSNV/x1Lr/W0oqdNnRzF/dkiCZ/00wsXW0w1RbafsaTIRyfnFRhLLzDmm4twZUBQx6E9hwbC7wUuKY3/IrMa9PWt9soHNj7sOtfN/e9Bj6Bz7RTvB7LJfJT4k0LCFoh/vBdBB3REFUSyb13HoPWREPLmHff/k7iJ4LS8mHdFijigekTd5N6EE0s9nT7cFkneiy115hdkRl6Lfd8lXumE1W3YuvvS6pdfVV0MzJU2zNM0wJc1s2LYmv+yGYev5cp1cUfd3Qrpmtkwj75CvmrauNfKbXeHdPQTeqLArMYjutqLJ72QYdNsswqXbdkN+NZoNu5UvdYX7WLPchO7Ds9RJPyHsutnSS8vrhm3kN1vXfYy43U/vw1W1UlH3MBOF6qpcc+yPSKjd0lt19vvovXWpWDFoVwX+LSN3tPsoXLwWrajrD0KXVjcNlSBDN5olyCxLV19GeWIBeFZ5Yq26Jb8sMFN9mU1TU6uaYdt27hj3CbGjr2jxpWN9hKN2J4e5Kscd19CVEDe/vH3SoW8YqjJq9ZYOKChpWu60VvTkd5LX0FqqlpqaoTVV3lr1ZpE3OJOq5ooCaeVOc0Wb/woVtWEYCi6a1TSaynhDtzSzcKNeVACt1SqAA0UfnJSset0WH2arblYUuV1rNrUChYYJMMwLTbKIWzrIlxTTaLXkdk1rli1Fa1mWXLSggpYks1WqNvTKxIbaZjTqudO4T5Y/OnmsVFNVs/8Iy8NbRxxqyqfUYHDUrufll5HfnnNWlHotA2nZDbvIK6RDyYfKoCALzaul53BTWRGzf5GQAdAqyJgtu95U0DIsVYm0ujgP+TZ0cksvUg+VS4FNb1qqDmkto25ohSlGZZTRmH/Z1ZdVfSnkgQKzXtHmUhpCa6NhVZxmMz8tB/GlJ5ZHwzU585BxFFOsHgvEzR3GN5j5wWG4w7vVlesshSEnYq7e9ika71Sj1lYaAbCOli/fPxquLQ8kIG48DrB/5ZiZejFQzwWxwCZ5ix/1iocaNwnSMYnaETSnl+IuUxAKS31AKJFPFr4cDNnVFg7OU5Kd3OSfb69eRqTfn8HQUJomHyDK0UUEIN+SIq+rafPdURSrCyjMeeLZgGXHynlxj00QOOzNaq/mIiDM3lTIhTAqw672U4blg4zwNe+Vot2zALZefYC37SM6vb6tfZ/BUAn5EhG8y5ZqqvqA3OH60si0gIhjWTLUu1okn9OyfTVzibcUUN5T/+CYX4A5LDuE3HMxzMFMASMey16qx6cCLCBEviA9XphffZgk4nE1xv5mW43Bw7Vq7Hc7YvcJbN4Wnr+AKbdWO66SWA3Qe4qzv9PpDt7//U+1n/zwfPL8wd9qtQfHSt/iMLjoNsMBQHJuwpYUMXw2t+BFARBhxCbEDkbWaWVQmb+2mL1rtb56/xRBU367er63ANv9JAaJkDQxGQ3UbCOgO3+AyE+Vpd5MvTH+vywbrstjdqMFFDjK5UuvXBZnb+1nw7X5kSxshetFIHIK56U0b4KRAKFYCVDC4HANv1h8A7n1ePer6oHy4IYZ/wU=]],
}
