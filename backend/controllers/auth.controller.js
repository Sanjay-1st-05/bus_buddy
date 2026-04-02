const { db } = require("../services/firebase.service");

const loginUser = async (req, res) => {
  try {
    const { id, password } = req.body;

    if (!id || !password) {
      return res.status(400).json({ message: "Missing fields" });
    }

    const userDoc = await db.collection("users").doc(id).get();

    if (!userDoc.exists) {
      return res.status(401).json({ message: "User not found" });
    }

    const user = userDoc.data();

    if (user.password !== password) {
      return res.status(401).json({ message: "Wrong password" });
    }

    return res.json({
      success: true,
      role: user.role,
    });
  } catch (error) {
    console.log(error);
    res.status(500).json({ message: "Server error" });
  }
};

module.exports = { loginUser };
