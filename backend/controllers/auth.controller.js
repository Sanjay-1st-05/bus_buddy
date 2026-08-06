const getSession = async (req, res) => {
  return res.json({
    success: true,
    uid: req.user.uid,
    role: req.role,
  });
};

module.exports = { getSession };
