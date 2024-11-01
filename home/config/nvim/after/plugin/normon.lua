local normon = require("normon")
-- cgn on current word/selection
normon("<space>n", "cgn")
normon("<space>N", "cgN")

-- macro on current word/selection
normon("<space>q", "qq")
normon("<space>Q", "qq", { backward = true })

-- improved * and #
-- escapes special characters and does not ignore case
normon("*", "n", { clearSearch = true })
normon("#", "n", { backward = true, clearSearch = true })

-- Jake has this:
--return {
--    "jake-stewart/normon.nvim",
--    keys = {
--        {"<leader>n", mode = {"n", "v"}},
--        {"<leader>N", mode = {"n", "v"}},
--        {"<leader>q", mode = {"n", "v"}},
--        {"<leader>Q", mdoe = {"n", "v"}},
--        {"*", mode = {"n", "v"}},
--        {"#", mode = {"n", "v"}},
--        {"<leader>dgn", mode = {"n", "v"}},
--        {"<leader>dgN", mdoe = {"n", "v"}},
--    },
--    config = function()
--        local normon = require("normon")
--        normon("<leader>n", "cgn")
--        normon("<leader>N", "cgN")
--        normon("<leader>q", "q")
--        normon("<leader>Q", "q", {backward = true})
--        normon("*", "n", {clearSearch = true})
--        normon("#", "n", {backward = true, clearSearch = true})
--
--        normon("<leader>dgn", "dgn")
--        normon("<leader>dgN", "dgN")
--    end
--}
