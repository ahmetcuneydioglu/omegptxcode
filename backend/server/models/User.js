const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  googleId: { type: String, unique: true, sparse: true },
  email: { type: String, unique: true, sparse: true },
  name: String,
  avatar: String,
  gender: { type: String, default: null },
  birthDate: { type: String, default: null },
  work: { type: String, default: null },
  education: { type: String, default: null },
  location: { type: String, default: null },
  hometown: { type: String, default: null },
  height: { type: Number, default: null },
  exercise: { type: String, default: null },
  lookingFor: { type: [String], default: [] },
  languages: { type: [String], default: [] },
  country: { type: String, default: null },
  countryFlag: { type: String, default: null },
  bio: { type: String, default: "", maxLength: 150 },
  photos: { type: [String], default: [] },
  interests: { type: [String], default: [] },
  badges: { type: [String], default: ["Yeni Üye"] },
  followersCount: { type: Number, default: 0 },
  followingCount: { type: Number, default: 0 },
  likes: { type: Number, default: 0 },
  isRegistered: { type: Boolean, default: false },
  role: { type: String, default: 'user' },
  trustScore: { type: Number, default: 100 },
  status: { type: String, default: 'active' },
  lastSeen: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now },
  gems: { type: Number, default: 25 },
  dailyStreak: { type: Number, default: 0 },
  lastLoginDate: { type: Date },
  lastClaimedDate: { type: Date }
});

module.exports = mongoose.models.User || mongoose.model('User', UserSchema);
