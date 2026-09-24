# Plugins

Everything in this folder is copied into Moodle's `public/` directory when the image is built. Put each plugin at the path Moodle expects, the same path its install instructions give relative to the Moodle root:

    plugins/mod/attendance/          -> public/mod/attendance
    plugins/theme/moove/             -> public/theme/moove
    plugins/local/staticpage/        -> public/local/staticpage

Commit, push and redeploy: the next start finds the new plugin and installs it, or upgrades it when you replace it with a newer version. Check each plugin supports Moodle 5.2 before adding it.
