max_line_length = 90

read_globals = {
    string = {fields = {'split', 'trim'}},
    table = {fields = {'copy', 'indexof', 'insert_all'}},
    'formspec_ast',
    'minetest',
    'flow',
    'verbana',
    'sway'
}

-- This error is thrown for methods that don't use the implicit "self"
-- parameter.
ignore = {"212/self", "432/player", "43/ctx", "212/player", "212/ctx", "212/value"}
