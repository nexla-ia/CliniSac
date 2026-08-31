import React, { useState } from 'react'
import { NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { LogOut, KeyRound } from 'lucide-react'
import ChangePasswordModal from './ChangePasswordModal'
import BrandMark from './BrandMark'
import './Sidebar.css'

export default function Sidebar({ links, role }) {
  const { session, logout } = useAuth()
  const navigate = useNavigate()
  const [pwModal, setPwModal] = useState(false)
  // Só usuário de empresa "de verdade" troca a senha (ADM global e suporte não).
  const canChangePassword = session?.user?.id && !session?.user?.master

  function handleLogout() {
    logout()
    navigate('/login')
  }

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <div className="sidebar-logo" style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
          <BrandMark size={32} />
          <span style={{ fontFamily: "'Bricolage Grotesque','DM Sans',sans-serif", fontWeight: 800, fontSize: 21, letterSpacing: '-0.02em', lineHeight: 1 }}>
            <span style={{ color: 'currentColor' }}>Clini</span><span style={{ color: '#12B6A6' }}>Sac</span>
          </span>
        </div>
        <div className="sidebar-brand-tag">{role === 'adm' ? 'ADM Global' : 'Painel'}</div>
      </div>

      <nav className="sidebar-nav">
        {links.map(link => link.section
          ? (
            <div key={`sec-${link.section}`} className="sidebar-section">{link.section}</div>
          )
          : link.onClick
          ? (
            <button
              key={link.key || link.label}
              type="button"
              onClick={link.onClick}
              className={`sidebar-link ${link.active ? 'active' : ''}`}>
              <link.icon size={16} />
              {link.label}
              {link.badge ? <span className={`sidebar-badge nx-badge nx-badge-${link.badgeColor || 'cyan'}`}>{link.badge}</span> : null}
            </button>
          )
          : (
            <NavLink key={link.to} to={link.to} end={link.end} className={({ isActive }) => `sidebar-link ${isActive ? 'active' : ''}`}>
              <link.icon size={16} />
              {link.label}
              {link.badge ? <span className={`sidebar-badge nx-badge nx-badge-${link.badgeColor || 'cyan'}`}>{link.badge}</span> : null}
            </NavLink>
          )
        )}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-user">
          <div className="sidebar-avatar">
            {session?.user?.name?.charAt(0).toUpperCase()}
          </div>
          <div className="sidebar-user-info">
            <div className="sidebar-user-name">{session?.user?.name}</div>
            <div className="sidebar-user-email">{session?.user?.email}</div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {canChangePassword && (
            <button className="sidebar-key" onClick={() => setPwModal(true)} title="Trocar senha">
              <KeyRound size={15} />
            </button>
          )}
          <button className="sidebar-logout" onClick={handleLogout} title="Sair">
            <LogOut size={15} />
          </button>
        </div>
      </div>

      {pwModal && <ChangePasswordModal onClose={() => setPwModal(false)} />}
    </aside>
  )
}

