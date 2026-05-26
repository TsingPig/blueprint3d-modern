'use client'

import React from 'react'
import { Button } from '@/components/ui/button'

interface Blueprint3DErrorBoundaryProps {
  children: React.ReactNode
}

interface Blueprint3DErrorBoundaryState {
  error: Error | null
}

export class Blueprint3DErrorBoundary extends React.Component<
  Blueprint3DErrorBoundaryProps,
  Blueprint3DErrorBoundaryState
> {
  state: Blueprint3DErrorBoundaryState = {
    error: null
  }

  static getDerivedStateFromError(error: Error): Blueprint3DErrorBoundaryState {
    return { error }
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('[Blueprint3DErrorBoundary] Render error:', error, errorInfo)
  }

  private handleReload = () => {
    window.location.reload()
  }

  render() {
    if (this.state.error) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-background px-6">
          <div className="w-full max-w-lg rounded-xl border border-border bg-card p-6 shadow-sm">
            <h1 className="text-lg font-semibold text-foreground">Blueprint3D failed to render</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              A client-side error interrupted the UI. Reloading the page usually fixes it.
            </p>
            <p className="mt-4 rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
              {this.state.error.message}
            </p>
            <div className="mt-5">
              <Button onClick={this.handleReload}>Reload Page</Button>
            </div>
          </div>
        </div>
      )
    }

    return this.props.children
  }
}
